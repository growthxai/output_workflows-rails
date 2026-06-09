# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ActiveRecord::Base
      # Cost rollup behavior for WorkflowExecution.
      #
      # Cost data arrives as a stream of per-event webhooks (one per LLM call,
      # one per HTTP call) appended via `Events#append_event`. This module owns
      # the rollup-column increments (`apply_rollups_for`) and the read surface
      # (`cost_payload`) that frontends consume.
      module Cost
        # Bump the rollup columns for a single event with one atomic
        # `UPDATE ... SET col = col + n WHERE id = ?` (via `update_counters`).
        # No `FOR UPDATE`, no dirty-attribute save — called from
        # `Events#append_event` right after the event row is inserted.
        # Note: this updates the database directly, so reload the record if you
        # need the new rollup values in memory.
        def apply_rollups_for(action_type, cost_micro:, usage:)
          increments =
            case action_type
            when "llm"
              {
                total_cost_micro_usd: cost_micro,
                total_llm_cost_micro_usd: cost_micro,
                total_tokens: usage[:totalTokens].to_i,
                total_input_tokens: usage[:inputTokens].to_i,
                total_output_tokens: usage[:outputTokens].to_i,
                total_cached_input_tokens: usage[:cachedInputTokens].to_i,
                total_reasoning_tokens: usage[:reasoningTokens].to_i
              }
            when "http_cost"
              {
                total_cost_micro_usd: cost_micro,
                total_http_cost_micro_usd: cost_micro
              }
            when "http"
              { total_http_calls: 1 }
            end

          # Single atomic UPDATE; skipping validations is intentional here.
          self.class.update_counters(id, increments) if increments # rubocop:disable Rails/SkipsModelValidations
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
