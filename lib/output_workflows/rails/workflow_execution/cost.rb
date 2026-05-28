# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution
      # Cost rollup behavior for WorkflowExecution.
      #
      # Cost data arrives as a stream of per-event webhooks (one per LLM call,
      # one per HTTP call). Each event is processed by the host application,
      # which calls `apply_cost_event!(payload)` on the matching execution row
      # to perform an idempotent, row-locked increment of the cost columns.
      #
      # The `RollupEvent` AR class backs the dedup table:
      # `output_workflow_execution_events`. Atlas (the consuming app) owns the
      # migration that creates it.
      module Cost
        extend ActiveSupport::Concern

        included do
          has_many :rollup_events,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution::RollupEvent",
                   foreign_key: :workflow_execution_id,
                   inverse_of: :workflow_execution,
                   dependent: :destroy
        end

        # Apply a single cost event to the execution row.
        #
        # Idempotent on `event_id` via a unique index on
        # `(workflow_execution_id, event_id)`. Returns `false` if the event is
        # a duplicate or if required fields are missing; returns `true` after a
        # successful apply.
        #
        # Supported actions:
        #   - "workflow_event.llm"       => increments total_cost_micro_usd +
        #                                    total_llm_cost_micro_usd +
        #                                    total_tokens / input / output / cached_input
        #   - "workflow_event.http_cost" => increments total_cost_micro_usd +
        #                                    total_http_cost_micro_usd
        #   - "workflow_event.http"      => increments total_http_calls
        #   - anything else              => no-op (dedup row still inserted)
        def apply_cost_event!(payload)
          payload  = payload.with_indifferent_access
          event_id = payload[:event_id].presence || payload[:eventId].presence
          action   = payload[:action].presence
          return false if event_id.blank? || action.blank?

          begin
            rollup_events.create!(event_id: event_id)
          rescue ::ActiveRecord::RecordNotUnique
            return false
          end

          with_lock do
            case action
            when "workflow_event.llm"
              cost_micro = (payload.dig(:cost, :total).to_f * 1_000_000).round
              increment :total_cost_micro_usd,      cost_micro
              increment :total_llm_cost_micro_usd,  cost_micro
              increment :total_tokens,              payload.dig(:usage, :totalTokens).to_i
              increment :total_input_tokens,        payload.dig(:usage, :inputTokens).to_i
              increment :total_output_tokens,       payload.dig(:usage, :outputTokens).to_i
              increment :total_cached_input_tokens, payload.dig(:usage, :cachedInputTokens).to_i
              save!
            when "workflow_event.http_cost"
              cost_micro = (payload.dig(:cost, :total).to_f * 1_000_000).round
              increment :total_cost_micro_usd,      cost_micro
              increment :total_http_cost_micro_usd, cost_micro
              save!
            when "workflow_event.http"
              increment :total_http_calls, 1
              save!
            end
          end

          true
        end

        def cost_payload
          return nil unless has_cost_data?

          {
            total_cost_usd: total_cost_micro_usd / 1_000_000.0,
            total_http_calls: total_http_calls,
            token_usage: {
              input_tokens: total_input_tokens,
              output_tokens: total_output_tokens,
              cached_input_tokens: total_cached_input_tokens,
              total_tokens: total_tokens
            },
            trace_url: nil,
            cost_components: cost_components_from_rollups
          }
        end

        private

        def has_cost_data?
          total_cost_micro_usd.positive? ||
            total_tokens.positive? ||
            total_http_calls.positive?
        end

        def cost_components_from_rollups
          components = []
          components << { name: "llm:usage",         value_cents: (total_llm_cost_micro_usd  / 10_000.0).round } if total_llm_cost_micro_usd.positive?
          components << { name: "http:request:cost", value_cents: (total_http_cost_micro_usd / 10_000.0).round } if total_http_cost_micro_usd.positive?
          components
        end
      end
    end
  end
end
