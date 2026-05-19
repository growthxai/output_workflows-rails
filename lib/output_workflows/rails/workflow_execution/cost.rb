# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
    end

    # Rollup of cost data onto the WorkflowExecution row.
    #
    # Cost.cost_payload returns the JSON contract the atlas frontend already
    # consumes (mirrors Analytics::ExecutionCost#as_payload). Returns nil when
    # nothing has been rolled up yet so atlas's serializer can omit the key.
    class WorkflowExecution
      module Cost
        extend ActiveSupport::Concern

        # Hash matching Analytics::ExecutionCost#as_payload, or nil when no
        # cost data has been rolled up yet.
        def cost_payload
          return nil unless has_cost_data?

          {
            total_cost_usd: total_cost_micro_usd / 1_000_000.0,
            total_http_calls: total_http_calls,
            runtime_ms: nil,
            token_usage: {
              "input_tokens" => 0,
              "output_tokens" => 0,
              "cached_input_tokens" => 0,
              "total_tokens" => total_tokens
            },
            trace_url: cost_data_value("trace_url"),
            cost_components: cost_data_value("cost_components") || []
          }
        end

        private
          def has_cost_data?
            total_cost_micro_usd.positive? ||
              total_tokens.positive? ||
              total_http_calls.positive?
          end

          def cost_data_value(key)
            data = cost_data
            return nil unless data.is_a?(Hash)

            data[key] || data[key.to_sym]
          end
      end
    end
  end
end
