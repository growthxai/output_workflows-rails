# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution
      # Rollup of workflow cost/usage data onto the WorkflowExecution row.
      #
      # On workflow completion, the Output API's GET /workflow/{id}/result
      # response carries an `aggregations` block of absolute totals and an
      # `attributes` array of individual cost contributors:
      #
      #   {
      #     "aggregations": {
      #       "cost":         { "total": <dollars> },
      #       "tokens":       { "total": <int> },
      #       "httpRequests": { "total": <int> }
      #     },
      #     "attributes": [
      #       { "type": "llm:usage", "modelId": "...", "total": 0.0012,
      #         "tokensUsed": 1234, "usage": [{ "type": "input", "amount": 800 }, ...] },
      #       { "type": "http:request:cost", "url": "...", "total": 0.5, ... },
      #       { "type": "http:request:count", "url": "...", ... }
      #     ]
      #   }
      #
      # `apply_workflow_result` is idempotent: aggregations are absolute
      # totals (not deltas), so calling twice with the same result hash
      # leaves the row unchanged.
      module Cost
        def apply_workflow_result(result)
          return if result.nil?

          aggs = result.aggregations || {}
          cost_total  = aggs.dig("cost", "total").to_f
          token_total = aggs.dig("tokens", "total").to_i
          http_total  = aggs.dig("httpRequests", "total").to_i

          update! \
            total_cost_micro_usd: (cost_total * 1_000_000).round,
            total_tokens: token_total,
            total_http_calls: http_total,
            attributes_data: result.attributes || []
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
            .map do |type, items|
              { name: type, value_cents: (items.sum { |a| a["total"].to_f } * 100).round }
            end
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
