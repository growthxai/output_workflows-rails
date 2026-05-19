# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
    end

    # Rollup of workflow cost/usage data onto the WorkflowExecution row.
    #
    # On workflow completion, the Output API's GET /workflow/{id}/result response
    # carries an `aggregations` block of absolute totals and an `attributes` array
    # of individual cost contributors:
    #
    #   {
    #     "aggregations": {
    #       "cost":         { "total": <dollars> },
    #       "tokens":       { "total": <int> },
    #       "httpRequests": { "total": <int> }
    #     },
    #     "attributes": [
    #       { "type": "llm:usage",          "modelId": "...", "total": 0.0012, ... },
    #       { "type": "http:request:cost",  "url": "...",     "total": 0.5,    ... },
    #       { "type": "http:request:count", "url": "...", ... }
    #     ]
    #   }
    #
    # `apply_workflow_result!` reads that envelope and stores the totals. It is
    # idempotent by construction: aggregations are absolute (not deltas), so
    # calling twice with the same result hash leaves the row unchanged.
    class WorkflowExecution
      module Cost
        extend ActiveSupport::Concern

        # Apply the final workflow result envelope. Idempotent by construction:
        # aggregations are absolute totals (not deltas), so calling twice with
        # the same result hash leaves the row unchanged. Attributes are the
        # final snapshot — same input, same output.
        def apply_workflow_result!(result)
          return if result.nil?

          aggs = result.aggregations || {}
          cost_total  = aggs.dig("cost", "total").to_f
          token_total = aggs.dig("tokens", "total").to_i
          http_total  = aggs.dig("httpRequests", "total").to_i

          update! \
            total_cost_micro_usd: (cost_total * 1_000_000).round,
            total_tokens:         token_total,
            total_http_calls:     http_total,
            attributes_data:      result.attributes || []
        end

        # Hash matching the atlas-frontend contract. Returns nil when no
        # workflow result has been applied yet so the serializer can omit
        # the cost block.
        def cost_payload
          return nil unless has_cost_data?

          {
            total_cost_usd:    total_cost_micro_usd / 1_000_000.0,
            total_http_calls:  total_http_calls,
            runtime_ms:        nil,
            token_usage: {
              "input_tokens"        => 0,
              "output_tokens"       => 0,
              "cached_input_tokens" => 0,
              "total_tokens"        => total_tokens
            },
            trace_url:        nil,
            cost_components:  cost_components_from_attributes
          }
        end

        private
          def has_cost_data?
            total_cost_micro_usd.positive? ||
              total_tokens.positive? ||
              total_http_calls.positive?
          end

          # Group attributes by type, sum totals, expose for the popover.
          def cost_components_from_attributes
            return [] unless attributes_data.is_a?(Array)

            attributes_data
              .group_by { |a| a["type"] }
              .map { |type, items|
                { "name" => type, "value_cents" => (items.sum { |a| a["total"].to_f } * 100).round }
              }
          end
      end
    end
  end
end
