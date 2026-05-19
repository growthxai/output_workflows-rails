# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
    end

    # Rollup of per-event cost data onto the WorkflowExecution row.
    #
    # The os-workflows usage_events hook forwards three webhook actions without
    # mutation, each carrying an `event_id` for idempotency:
    #
    #   workflow_event.llm        cost.total, usage.totalTokens, modelId, …
    #   workflow_event.http_cost  cost.total, url, …
    #   workflow_event.http       method, url, status, durationMs, outcome, …
    #
    # Cost.apply_cost_event! is the entrypoint. It:
    #   1. Records the event in `output_workflow_execution_events` (the unique
    #      index `(workflow_execution_id, event_id)` is the dedup gate).
    #   2. Increments the matching rollup column inside a row lock so concurrent
    #      webhooks for the same execution serialize.
    #
    # Cost.cost_payload returns the JSON contract the atlas frontend already
    # consumes (mirrors Analytics::ExecutionCost#as_payload). Returns nil when
    # nothing has been rolled up yet so atlas's serializer can omit the key.
    class WorkflowExecution
      module Cost
        extend ActiveSupport::Concern

        included do
          has_many :rollup_events,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution::RollupEvent",
                   dependent: :destroy
        end

        # Idempotently apply a single usage event. Returns true when the event
        # was applied for the first time, false when it was already recorded.
        def apply_cost_event!(payload)
          payload = payload.with_indifferent_access unless payload.is_a?(ActiveSupport::HashWithIndifferentAccess)

          event_id = payload[:event_id] || payload[:eventId]
          action   = payload[:action]
          return false if event_id.blank? || action.blank?

          begin
            rollup_events.create!(event_id: event_id)
          rescue ActiveRecord::RecordNotUnique
            return false
          end

          with_lock do
            case action
            when "workflow_event.llm"
              apply_llm_event(payload)
            when "workflow_event.http_cost"
              apply_http_cost_event(payload)
            when "workflow_event.http"
              apply_http_event
            end
          end

          true
        end

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
          def apply_llm_event(payload)
            cost_total   = payload.dig(:cost, :total).to_f
            total_tokens_for_event = payload.dig(:usage, :totalTokens).to_i

            update! \
              total_cost_micro_usd: total_cost_micro_usd + (cost_total * 1_000_000).round,
              total_tokens: total_tokens + total_tokens_for_event
          end

          def apply_http_cost_event(payload)
            cost_total = payload.dig(:cost, :total).to_f

            update! total_cost_micro_usd: total_cost_micro_usd + (cost_total * 1_000_000).round
          end

          def apply_http_event
            update! total_http_calls: total_http_calls + 1
          end

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
