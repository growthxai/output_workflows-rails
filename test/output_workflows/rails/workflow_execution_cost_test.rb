# frozen_string_literal: true

require "test_helper"
require "active_support/test_case"

module OutputWorkflows
  module Rails
    class WorkflowExecutionCostTest < ActiveSupport::TestCase
      WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution
      WorkflowResult    = OutputWorkflows::Responses::WorkflowResult

      setup do
        WorkflowExecution.delete_all
        @execution = WorkflowExecution.create!(
          workflow_id: "wf_abc123",
          workflow_run_id: "run_abc123",
          workflow_name: "context_persona_enrichment",
          status: "pending"
        )
      end

      # --- apply_workflow_result -----------------------------------------

      test "apply_workflow_result with nil is a noop" do
        @execution.apply_workflow_result(nil)
        @execution.reload

        assert_equal 0, @execution.total_cost_micro_usd
        assert_equal 0, @execution.total_tokens
        assert_equal 0, @execution.total_http_calls
      end

      test "apply_workflow_result writes aggregations and attributes" do
        result = build_result(
          cost: 0.123456,
          tokens: 1_234,
          http_requests: 3,
          attributes: [
            { "type" => "llm:usage",         "modelId" => "claude", "total" => 0.1, "tokensUsed" => 1_000 },
            { "type" => "http:request:cost", "url" => "https://x.test", "total" => 0.02 }
          ]
        )

        @execution.apply_workflow_result(result)
        @execution.reload

        assert_equal 123_456, @execution.total_cost_micro_usd
        assert_equal 1_234,   @execution.total_tokens
        assert_equal 3,       @execution.total_http_calls
        assert_equal 2,       @execution.attributes_data.length
        assert_equal "llm:usage", @execution.attributes_data.first["type"]
      end

      test "apply_workflow_result is idempotent on same input" do
        result = build_result(cost: 0.5, tokens: 100, http_requests: 2, attributes: [
                                { "type" => "llm:usage", "total" => 0.5 }
                              ])

        @execution.apply_workflow_result(result)
        @execution.reload
        snapshot = {
          cost: @execution.total_cost_micro_usd,
          toks: @execution.total_tokens,
          http: @execution.total_http_calls,
          attrs: @execution.attributes_data
        }

        @execution.apply_workflow_result(result)
        @execution.reload

        assert_equal snapshot[:cost], @execution.total_cost_micro_usd
        assert_equal snapshot[:toks], @execution.total_tokens
        assert_equal snapshot[:http], @execution.total_http_calls
        assert_equal snapshot[:attrs], @execution.attributes_data
      end

      test "apply_workflow_result overwrites with new aggregations" do
        @execution.apply_workflow_result(build_result(cost: 0.5, tokens: 100, http_requests: 5))
        @execution.reload
        assert_equal 500_000, @execution.total_cost_micro_usd
        assert_equal 100,     @execution.total_tokens
        assert_equal 5,       @execution.total_http_calls

        @execution.apply_workflow_result(build_result(cost: 1.0, tokens: 50, http_requests: 1))
        @execution.reload

        # Overwrites, never accumulates
        assert_equal 1_000_000, @execution.total_cost_micro_usd
        assert_equal 50,        @execution.total_tokens
        assert_equal 1,         @execution.total_http_calls
      end

      test "apply_workflow_result handles missing aggregations" do
        result = WorkflowResult.new(workflow_id: "wf_abc123", output: {}, trace: {})

        @execution.apply_workflow_result(result)
        @execution.reload

        assert_equal 0,  @execution.total_cost_micro_usd
        assert_equal 0,  @execution.total_tokens
        assert_equal 0,  @execution.total_http_calls
        assert_equal [], @execution.attributes_data
      end

      # --- cost_payload --------------------------------------------------

      test "cost_payload returns nil when no data" do
        assert_nil @execution.cost_payload
      end

      test "cost_payload returns contract shape when data present" do
        @execution.apply_workflow_result(build_result(
                                           cost: 0.5,
                                           tokens: 1_000,
                                           http_requests: 2,
                                           attributes: []
                                         ))

        payload = @execution.reload.cost_payload

        assert_in_delta 0.5, payload[:total_cost_usd], 1e-9
        assert_equal 2,    payload[:total_http_calls]
        refute_includes    payload.keys, :runtime_ms
        assert_equal({
                       input_tokens: 0,
                       output_tokens: 0,
                       cached_input_tokens: 0,
                       total_tokens: 1_000
                     }, payload[:token_usage])
        assert_nil       payload[:trace_url]
        assert_equal [], payload[:cost_components]
      end

      test "cost_payload derives components grouped by type" do
        @execution.apply_workflow_result(build_result(
                                           cost: 0.4,
                                           tokens: 100,
                                           http_requests: 1,
                                           attributes: [
                                             { "type" => "llm:usage",         "total" => 0.1 },
                                             { "type" => "llm:usage",         "total" => 0.2 },
                                             { "type" => "http:request:cost", "total" => 0.1 }
                                           ]
                                         ))

        components = @execution.reload.cost_payload[:cost_components]

        by_name = components.index_by { |c| c[:name] }
        assert_equal 30, by_name["llm:usage"][:value_cents]
        assert_equal 10, by_name["http:request:cost"][:value_cents]
      end

      test "cost_payload sums input/output/cached tokens from llm:usage attributes" do
        @execution.apply_workflow_result(build_result(
                                           cost: 0.1,
                                           tokens: 1_000,
                                           http_requests: 0,
                                           attributes: [
                                             {
                                               "type" => "llm:usage",
                                               "total" => 0.1,
                                               "usage" => [
                                                 { "type" => "input",        "amount" => 600 },
                                                 { "type" => "output",       "amount" => 350 },
                                                 { "type" => "input_cached", "amount" => 50 }
                                               ]
                                             },
                                             {
                                               "type" => "llm:usage",
                                               "total" => 0.0,
                                               "usage" => [
                                                 { "type" => "input",  "amount" => 100 },
                                                 { "type" => "output", "amount" => 50 }
                                               ]
                                             }
                                           ]
                                         ))

        payload = @execution.reload.cost_payload

        assert_equal 700, payload[:token_usage][:input_tokens]
        assert_equal 400, payload[:token_usage][:output_tokens]
        assert_equal 50,  payload[:token_usage][:cached_input_tokens]
        assert_equal 1_000, payload[:token_usage][:total_tokens]
      end

      # --- mark_completed! ----------------------------------------------

      test "mark_completed with result writes status and rollup" do
        result = build_result(cost: 0.25, tokens: 500, http_requests: 4)

        @execution.mark_completed!(result: result)
        @execution.reload

        assert @execution.status_completed?
        refute_nil @execution.completed_at
        assert_equal 250_000, @execution.total_cost_micro_usd
        assert_equal 500,     @execution.total_tokens
        assert_equal 4,       @execution.total_http_calls
      end

      test "mark_completed without result only writes status" do
        @execution.mark_completed!
        @execution.reload

        assert @execution.status_completed?
        refute_nil @execution.completed_at
        assert_equal 0, @execution.total_cost_micro_usd
        assert_equal 0, @execution.total_tokens
        assert_equal 0, @execution.total_http_calls
      end

      private

      def build_result(cost:, tokens:, http_requests:, attributes: [])
        WorkflowResult.new(
          workflow_id: @execution.workflow_id,
          output: {},
          trace: {},
          aggregations: {
            "cost" => { "total" => cost },
            "tokens" => { "total" => tokens },
            "httpRequests" => { "total" => http_requests }
          },
          attributes: attributes
        )
      end
    end
  end
end
