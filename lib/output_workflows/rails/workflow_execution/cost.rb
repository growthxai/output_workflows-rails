# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      # Cost rollup behavior for WorkflowExecution.
      #
      # Cost data arrives as a stream of per-event webhooks (one per LLM call,
      # one per HTTP call) appended via `Events#append_event`. This module owns
      # the rollup-column increments (`apply_rollups_for`) and the read surface
      # (`cost_payload`) that frontends consume.
      module Cost
        # Increment the rollup columns for a single event. Called from
        # `Events#append_event` inside the `with_lock` block — does not save.
        def apply_rollups_for(action_type, cost_micro:, usage:)
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
