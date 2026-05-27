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
        #   - "workflow_event.llm"       => increments total_cost_micro_usd + total_tokens
        #   - "workflow_event.http_cost" => increments total_cost_micro_usd
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
              increment :total_cost_micro_usd, (payload.dig(:cost, :total).to_f * 1_000_000).round
              increment :total_tokens, payload.dig(:usage, :totalTokens).to_i
              save!
            when "workflow_event.http_cost"
              increment :total_cost_micro_usd, (payload.dig(:cost, :total).to_f * 1_000_000).round
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
            runtime_ms: nil,
            token_usage: {
              input_tokens: sum_usage_tokens("input"),
              output_tokens: sum_usage_tokens("output"),
              cached_input_tokens: sum_usage_tokens("input_cached"),
              total_tokens: total_tokens
            },
            trace_url: nil,
            cost_components: cost_components_from_attributes
          }
        end

        private

        def has_cost_data?
          total_cost_micro_usd.positive? ||
            total_tokens.positive? ||
            total_http_calls.positive?
        end

        def cost_components_from_attributes
          return [] unless attributes_data.is_a?(Array)

          attributes_data
            .group_by { |a| a["type"] }
            .map { |type, items| { name: type, value_cents: (items.sum { |a| a["total"].to_f } * 100).round } }
        end

        def sum_usage_tokens(usage_type)
          return 0 unless attributes_data.is_a?(Array)

          attributes_data
            .select { |a| a["type"] == "llm:usage" && a["usage"].is_a?(Array) }
            .flat_map { |a| a["usage"] }
            .select { |u| u["type"] == usage_type }
            .sum { |u| u["amount"].to_i }
        end
      end
    end
  end
end
