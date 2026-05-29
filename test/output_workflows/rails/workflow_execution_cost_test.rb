# frozen_string_literal: true

require "test_helper"
require "active_support/test_case"

module OutputWorkflows
  module Rails
    class WorkflowExecutionCostTest < ActiveSupport::TestCase
      WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution
      RollupEvent       = OutputWorkflows::Rails::WorkflowExecution::RollupEvent

      setup do
        RollupEvent.delete_all
        WorkflowExecution.delete_all
        @execution = WorkflowExecution.create!(
          workflow_id: "wf_abc123",
          workflow_run_id: "run_abc123",
          workflow_name: "context_persona_enrichment",
          status: "pending"
        )
      end

      # --- apply_cost_event! ---------------------------------------------

      test "llm event increments total_cost_micro_usd, llm cost rollup, and per-type tokens" do
        result = @execution.apply_cost_event!(
          llm_event(
            id: "evt_1",
            cost: 0.123456,
            total_tokens: 1_234,
            input_tokens: 800,
            output_tokens: 400,
            cached_input_tokens: 34
          )
        )
        @execution.reload

        assert_equal true, result
        assert_equal 123_456, @execution.total_cost_micro_usd
        assert_equal 123_456, @execution.total_llm_cost_micro_usd
        assert_equal 0,       @execution.total_http_cost_micro_usd
        assert_equal 1_234,   @execution.total_tokens
        assert_equal 800,     @execution.total_input_tokens
        assert_equal 400,     @execution.total_output_tokens
        assert_equal 34,      @execution.total_cached_input_tokens
        assert_equal 0,       @execution.total_http_calls
      end

      test "http_cost event increments total_cost_micro_usd and http cost rollup" do
        result = @execution.apply_cost_event!(http_cost_event(id: "evt_h", cost: 0.05))
        @execution.reload

        assert_equal true, result
        assert_equal 50_000, @execution.total_cost_micro_usd
        assert_equal 0,      @execution.total_llm_cost_micro_usd
        assert_equal 50_000, @execution.total_http_cost_micro_usd
        assert_equal 0,      @execution.total_tokens
        assert_equal 0,      @execution.total_http_calls
      end

      test "http event increments total_http_calls only" do
        result = @execution.apply_cost_event!(http_event(id: "evt_h2"))
        @execution.reload

        assert_equal true, result
        assert_equal 0, @execution.total_cost_micro_usd
        assert_equal 0, @execution.total_tokens
        assert_equal 1, @execution.total_http_calls
      end

      test "events of the same kind accumulate sequentially" do
        @execution.apply_cost_event!(llm_event(id: "evt_a", cost: 0.10, total_tokens: 100, input_tokens: 70, output_tokens: 30))
        @execution.apply_cost_event!(llm_event(id: "evt_b", cost: 0.25, total_tokens: 250, input_tokens: 150, output_tokens: 100))
        @execution.apply_cost_event!(http_event(id: "evt_c"))
        @execution.apply_cost_event!(http_event(id: "evt_d"))
        @execution.apply_cost_event!(http_cost_event(id: "evt_e", cost: 0.01))
        @execution.reload

        assert_equal 360_000, @execution.total_cost_micro_usd
        assert_equal 350_000, @execution.total_llm_cost_micro_usd
        assert_equal 10_000,  @execution.total_http_cost_micro_usd
        assert_equal 350,     @execution.total_tokens
        assert_equal 220,     @execution.total_input_tokens
        assert_equal 130,     @execution.total_output_tokens
        assert_equal 0,       @execution.total_cached_input_tokens
        assert_equal 2,       @execution.total_http_calls
      end

      test "llm event increments total_reasoning_tokens from usage.reasoningTokens" do
        result = @execution.apply_cost_event!(
          llm_event(
            id: "evt_reason",
            cost: 0.05,
            total_tokens: 100,
            input_tokens: 30,
            output_tokens: 70,
            reasoning_tokens: 42
          )
        )
        @execution.reload

        assert_equal true, result
        assert_equal 42, @execution.total_reasoning_tokens
      end

      test "reasoning tokens accumulate across multiple llm events" do
        @execution.apply_cost_event!(llm_event(id: "evt_r1", cost: 0.01, total_tokens: 50,  reasoning_tokens: 10))
        @execution.apply_cost_event!(llm_event(id: "evt_r2", cost: 0.02, total_tokens: 80,  reasoning_tokens: 25))
        @execution.apply_cost_event!(llm_event(id: "evt_r3", cost: 0.03, total_tokens: 120, reasoning_tokens: 7))
        @execution.reload

        assert_equal 42, @execution.total_reasoning_tokens
      end

      test "duplicate event_id returns false and does not double-increment" do
        first = @execution.apply_cost_event!(
          llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40, cached_input_tokens: 10)
        )
        dup = @execution.apply_cost_event!(
          llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40, cached_input_tokens: 10)
        )
        @execution.reload

        assert_equal true,  first
        assert_equal false, dup
        assert_equal 100_000, @execution.total_cost_micro_usd
        assert_equal 100_000, @execution.total_llm_cost_micro_usd
        assert_equal 100,     @execution.total_tokens
        assert_equal 60,      @execution.total_input_tokens
        assert_equal 40,      @execution.total_output_tokens
        assert_equal 10,      @execution.total_cached_input_tokens
        assert_equal 1, RollupEvent.where(workflow_execution_id: @execution.id, event_id: "evt_dup").count
      end

      test "accepts camelCase eventId alias" do
        result = @execution.apply_cost_event!(
          "eventId" => "evt_camel",
          "action"  => "workflow_event.llm",
          "cost"    => { "total" => 0.05 },
          "usage"   => { "totalTokens" => 42 }
        )
        @execution.reload

        assert_equal true, result
        assert_equal 50_000, @execution.total_cost_micro_usd
        assert_equal 42,     @execution.total_tokens
      end

      test "missing event_id returns false and does not insert dedup row" do
        result = @execution.apply_cost_event!(
          "action" => "workflow_event.llm",
          "cost"   => { "total" => 0.10 },
          "usage"  => { "totalTokens" => 100 }
        )

        assert_equal false, result
        assert_equal 0, RollupEvent.count
        assert_equal 0, @execution.reload.total_cost_micro_usd
      end

      test "missing action returns false and does not insert dedup row" do
        result = @execution.apply_cost_event!(
          "event_id" => "evt_noop",
          "cost"     => { "total" => 0.10 }
        )

        assert_equal false, result
        assert_equal 0, RollupEvent.count
      end

      test "unknown action no-ops but still records dedup row" do
        result = @execution.apply_cost_event!(
          "event_id" => "evt_unknown",
          "action"   => "workflow_event.unknown"
        )
        @execution.reload

        assert_equal true, result
        assert_equal 0, @execution.total_cost_micro_usd
        assert_equal 0, @execution.total_tokens
        assert_equal 0, @execution.total_http_calls
        assert_equal 1, RollupEvent.where(event_id: "evt_unknown").count
      end

      test "dedup is scoped per execution — same event_id under a different execution is allowed" do
        other = WorkflowExecution.create!(
          workflow_id: "wf_other",
          workflow_run_id: "run_other",
          workflow_name: "context_persona_enrichment",
          status: "pending"
        )

        @execution.apply_cost_event!(llm_event(id: "evt_same", cost: 0.10, total_tokens: 100))
        other.apply_cost_event!(llm_event(id: "evt_same", cost: 0.20, total_tokens: 200))

        assert_equal 100_000, @execution.reload.total_cost_micro_usd
        assert_equal 200_000, other.reload.total_cost_micro_usd
      end

      # --- cost_payload --------------------------------------------------

      test "cost_payload returns nil when no data" do
        assert_nil @execution.cost_payload
      end

      test "cost_payload returns contract shape from columns" do
        @execution.apply_cost_event!(
          llm_event(
            id: "evt_p1",
            cost: 0.40,
            total_tokens: 1_000,
            input_tokens: 700,
            output_tokens: 250,
            cached_input_tokens: 50
          )
        )
        @execution.apply_cost_event!(http_cost_event(id: "evt_p2", cost: 0.10))
        @execution.apply_cost_event!(http_event(id: "evt_p3"))
        @execution.apply_cost_event!(http_event(id: "evt_p4"))

        payload = @execution.reload.cost_payload

        assert_in_delta 0.5, payload[:total_cost_usd], 1e-9
        assert_equal 2,    payload[:total_http_calls]
        refute_includes    payload.keys, :runtime_ms
        assert_equal({
                       input_tokens: 700,
                       output_tokens: 250,
                       cached_input_tokens: 50,
                       reasoning_tokens: 0,
                       total_tokens: 1_000
                     }, payload[:token_usage])
        assert_nil payload[:trace_url]
        assert_equal(
          [
            { name: "llm:usage",         value_cents: 40 },
            { name: "http:request:cost", value_cents: 10 }
          ],
          payload[:cost_components]
        )
      end

      test "cost_payload token_usage reflects total_reasoning_tokens column" do
        @execution.apply_cost_event!(
          llm_event(
            id: "evt_pr",
            cost: 0.10,
            total_tokens: 200,
            input_tokens: 120,
            output_tokens: 80,
            reasoning_tokens: 17
          )
        )

        payload = @execution.reload.cost_payload

        assert_equal 17, payload[:token_usage][:reasoning_tokens]
      end

      test "cost_payload cost_components only includes http when no llm events" do
        @execution.apply_cost_event!(http_cost_event(id: "evt_h1", cost: 0.07))
        @execution.apply_cost_event!(http_event(id: "evt_h2"))

        payload = @execution.reload.cost_payload

        assert_in_delta 0.07, payload[:total_cost_usd], 1e-9
        assert_equal 1, payload[:total_http_calls]
        assert_equal({
                       input_tokens: 0,
                       output_tokens: 0,
                       cached_input_tokens: 0,
                       reasoning_tokens: 0,
                       total_tokens: 0
                     }, payload[:token_usage])
        assert_equal(
          [{ name: "http:request:cost", value_cents: 7 }],
          payload[:cost_components]
        )
      end

      # --- mark_completed! ----------------------------------------------

      test "mark_completed! does not touch cost columns" do
        @execution.apply_cost_event!(llm_event(id: "evt_pre", cost: 0.10, total_tokens: 100))
        @execution.mark_completed!
        @execution.reload

        assert @execution.status_completed?
        refute_nil @execution.completed_at
        # Cost rollup preserved as written by per-event hooks; lifecycle did not touch it.
        assert_equal 100_000, @execution.total_cost_micro_usd
        assert_equal 100,     @execution.total_tokens
      end

      test "mark_completed!(result:) is a state-only transition (result is ignored)" do
        result = OutputWorkflows::Responses::WorkflowResult.new(
          workflow_id: @execution.workflow_id,
          output: {},
          trace: {},
          aggregations: {
            "cost" => { "total" => 99 },
            "tokens" => { "total" => 99 },
            "httpRequests" => { "total" => 99 }
          },
          attributes: []
        )

        @execution.mark_completed!(result: result)
        @execution.reload

        assert @execution.status_completed?
        assert_equal 0, @execution.total_cost_micro_usd
        assert_equal 0, @execution.total_tokens
        assert_equal 0, @execution.total_http_calls
      end

      private

      def llm_event(id:, cost:, total_tokens:, input_tokens: 0, output_tokens: 0, cached_input_tokens: 0, reasoning_tokens: 0)
        {
          "event_id" => id,
          "action"   => "workflow_event.llm",
          "cost"     => { "total" => cost },
          "usage"    => {
            "totalTokens"       => total_tokens,
            "inputTokens"       => input_tokens,
            "outputTokens"      => output_tokens,
            "cachedInputTokens" => cached_input_tokens,
            "reasoningTokens"   => reasoning_tokens
          }
        }
      end

      def http_cost_event(id:, cost:)
        {
          "event_id" => id,
          "action"   => "workflow_event.http_cost",
          "cost"     => { "total" => cost }
        }
      end

      def http_event(id:)
        {
          "event_id" => id,
          "action"   => "workflow_event.http"
        }
      end
    end
  end
end
