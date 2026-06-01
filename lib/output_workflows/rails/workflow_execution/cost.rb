# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      # Cost rollup behavior for WorkflowExecution.
      #
      # Cost data arrives as a stream of per-event webhooks (one per LLM call,
      # one per HTTP call). Each event is processed by the host application,
      # which calls `apply_cost_event!(payload)` on the matching execution row
      # to perform an idempotent, row-locked increment of the cost columns and
      # append the per-event detail to the `cost_events` JSONB array.
      module Cost
        extend ActiveSupport::Concern

        # Apply a single cost event to the execution row.
        #
        # Idempotent on event_id via membership check on the cost_events
        # JSONB array. Returns true on first apply, false on duplicate or
        # missing required fields.
        def apply_cost_event!(payload)
          payload  = payload.with_indifferent_access
          event_id = payload[:event_id].presence || payload[:eventId].presence
          action   = payload[:action].presence
          return false if event_id.blank? || action.blank?

          action_type = action.sub("workflow_event.", "")
          cost_micro  = (payload.dig(:cost, :total).to_f * 1_000_000).round
          usage       = payload[:usage] || {}

          with_lock do
            return false if cost_events.any? { |e| e["event_id"] == event_id }

            self.cost_events = cost_events + [{
              event_id:            event_id,
              action_type:         action_type,
              workflow_name:       workflow_name,
              provider:            payload[:provider],
              model_id:            payload[:modelId],
              url:                 payload[:url],
              cost_micro_usd:      cost_micro,
              input_tokens:        usage[:inputTokens].to_i,
              output_tokens:       usage[:outputTokens].to_i,
              cached_input_tokens: usage[:cachedInputTokens].to_i,
              reasoning_tokens:    usage[:reasoningTokens].to_i,
              total_tokens:        usage[:totalTokens].to_i,
              duration_ms:         payload[:durationMs],
              occurred_at:         Time.current.utc.iso8601
            }]

            case action_type
            when "llm"
              increment :total_cost_micro_usd,      cost_micro
              increment :total_llm_cost_micro_usd,  cost_micro
              increment :total_tokens,              usage[:totalTokens].to_i
              increment :total_input_tokens,        usage[:inputTokens].to_i
              increment :total_output_tokens,       usage[:outputTokens].to_i
              increment :total_cached_input_tokens, usage[:cachedInputTokens].to_i
              increment :total_reasoning_tokens,    usage[:reasoningTokens].to_i
            when "http_cost"
              increment :total_cost_micro_usd,      cost_micro
              increment :total_http_cost_micro_usd, cost_micro
            when "http"
              increment :total_http_calls, 1
            end
            save!
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
              reasoning_tokens: total_reasoning_tokens,
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
