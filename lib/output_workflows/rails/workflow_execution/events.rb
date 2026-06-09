# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ActiveRecord::Base
      module Events
        extend ActiveSupport::Concern

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
