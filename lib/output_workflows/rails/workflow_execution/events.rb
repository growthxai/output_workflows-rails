# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      # Append-only event log for the execution. Each call inserts one row into
      # `output_workflow_execution_events` (see WorkflowExecution::Event) and
      # atomically bumps the rollup columns via `Cost#apply_rollups_for`.
      #
      # Each event is one webhook (LLM call, HTTP call, etc.) from the
      # workflow's runtime. Dedup is enforced by the `UNIQUE (execution_id,
      # event_id)` index — a duplicate INSERT raises `RecordNotUnique`, which we
      # swallow and return false for. The INSERT + rollup run in one transaction
      # so a duplicate rolls back without double-counting; there is no
      # `FOR UPDATE` on the parent row and no JSONB array rewrite.
      module Events
        extend ActiveSupport::Concern

        # Record one webhook event. Idempotent on event_id. Returns true on
        # first apply, false on duplicate or missing required fields.
        def append_event(payload)
          payload  = payload.with_indifferent_access
          event_id = payload[:event_id].presence || payload[:eventId].presence
          action   = payload[:action].presence
          return false if event_id.blank? || action.blank?

          action_type = action.sub("workflow_event.", "")
          cost_micro  = (payload.dig(:cost, :total).to_f * 1_000_000).round
          usage       = payload[:usage] || {}
          entry_cost_micro = action_type == "http" ? 0 : cost_micro

          transaction do
            execution_events.create!(
              event_id: event_id,
              action_type: action_type,
              workflow_name: workflow_name,
              provider: payload[:provider],
              model_id: payload[:modelId],
              url: payload[:url],
              cost_micro_usd: entry_cost_micro,
              input_tokens: usage[:inputTokens].to_i,
              output_tokens: usage[:outputTokens].to_i,
              cached_input_tokens: usage[:cachedInputTokens].to_i,
              reasoning_tokens: usage[:reasoningTokens].to_i,
              total_tokens: usage[:totalTokens].to_i,
              duration_ms: payload[:durationMs],
              occurred_at: Time.current.utc
            )

            apply_rollups_for(action_type, cost_micro: cost_micro, usage: usage)
          end
          true
        rescue ActiveRecord::RecordNotUnique
          false
        end
      end
    end
  end
end
