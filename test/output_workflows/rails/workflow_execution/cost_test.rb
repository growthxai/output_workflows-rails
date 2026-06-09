# frozen_string_literal: true

require "test_helper"
require "active_support/test_case"

module OutputWorkflows
  module Rails
    class WorkflowExecution
      class CostTest < ActiveSupport::TestCase
        WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution

        setup do
          WorkflowExecution.delete_all
          @execution = WorkflowExecution.create!(
            workflow_id: "wf_abc123",
            workflow_run_id: "run_abc123",
            workflow_name: "context_persona_enrichment",
            status: "pending"
          )
        end

        # --- append_event ---------------------------------------------

        test "llm event appends one events entry with all the right fields" do
          result = @execution.append_event(
            llm_event(
              id: "evt_1",
              cost: 0.123456,
              total_tokens: 1_234,
              input_tokens: 800,
              output_tokens: 400,
              cached_input_tokens: 34,
              reasoning_tokens: 12,
              provider: "openai",
              model_id: "gpt-4o",
              url: "https://api.openai.com/v1/chat/completions",
              duration_ms: 1_500
            )
          )
          @execution.reload

          assert_equal true, result
          assert_equal 1, @execution.events.count

          entry = @execution.events.first
          assert_equal "evt_1",                                       entry.event_id
          assert_equal "llm",                                         entry.action_type
          assert_equal "context_persona_enrichment",                  entry.workflow_name
          assert_equal "openai",                                      entry.provider
          assert_equal "gpt-4o",                                      entry.model_id
          assert_equal "https://api.openai.com/v1/chat/completions",  entry.url
          assert_equal 123_456,                                       entry.cost_micro_usd
          assert_equal 800,                                           entry.input_tokens
          assert_equal 400,                                           entry.output_tokens
          assert_equal 34,                                            entry.cached_input_tokens
          assert_equal 12,                                            entry.reasoning_tokens
          assert_equal 1_234,                                         entry.total_tokens
          assert_equal 1_500,                                         entry.duration_ms
          refute_nil entry.occurred_at
        end

        test "llm event increments all 7 llm rollups" do
          @execution.append_event(
            llm_event(
              id: "evt_1",
              cost: 0.123456,
              total_tokens: 1_234,
              input_tokens: 800,
              output_tokens: 400,
              cached_input_tokens: 34,
              reasoning_tokens: 12
            )
          )
          @execution.reload

          assert_equal 123_456, @execution.total_cost_micro_usd
          assert_equal 123_456, @execution.total_llm_cost_micro_usd
          assert_equal 0,       @execution.total_http_cost_micro_usd
          assert_equal 1_234,   @execution.total_tokens
          assert_equal 800,     @execution.total_input_tokens
          assert_equal 400,     @execution.total_output_tokens
          assert_equal 34,      @execution.total_cached_input_tokens
          assert_equal 12,      @execution.total_reasoning_tokens
          assert_equal 0,       @execution.total_http_calls
        end

        test "http_cost event appends one events entry and increments cost columns only" do
          result = @execution.append_event(http_cost_event(id: "evt_h", cost: 0.05))
          @execution.reload

          assert_equal true, result
          assert_equal 1, @execution.events.count

          entry = @execution.events.first
          assert_equal "evt_h",     entry.event_id
          assert_equal "http_cost", entry.action_type
          assert_equal 50_000,      entry.cost_micro_usd
          assert_equal 0,           entry.total_tokens

          assert_equal 50_000, @execution.total_cost_micro_usd
          assert_equal 0,      @execution.total_llm_cost_micro_usd
          assert_equal 50_000, @execution.total_http_cost_micro_usd
          assert_equal 0,      @execution.total_tokens
          assert_equal 0,      @execution.total_input_tokens
          assert_equal 0,      @execution.total_output_tokens
          assert_equal 0,      @execution.total_cached_input_tokens
          assert_equal 0,      @execution.total_reasoning_tokens
          assert_equal 0,      @execution.total_http_calls
        end

        test "http action_type records cost_micro_usd: 0 on the event row even when payload has cost" do
          result = @execution.append_event(
            "event_id" => "evt_http_cost",
            "action"   => "workflow_event.http",
            "cost"     => { "total" => 0.001 },
            "url"      => "https://api.example.com/things"
          )
          @execution.reload

          assert_equal true, result
          entry = @execution.events.first
          assert_equal 0, entry.cost_micro_usd
          assert_equal 0, @execution.total_cost_micro_usd
          assert_equal 1, @execution.total_http_calls
        end

        test "http event appends one events entry and increments total_http_calls only" do
          result = @execution.append_event(http_event(id: "evt_h2"))
          @execution.reload

          assert_equal true, result
          assert_equal 1, @execution.events.count

          entry = @execution.events.first
          assert_equal "evt_h2", entry.event_id
          assert_equal "http",   entry.action_type

          assert_equal 0, @execution.total_cost_micro_usd
          assert_equal 0, @execution.total_llm_cost_micro_usd
          assert_equal 0, @execution.total_http_cost_micro_usd
          assert_equal 0, @execution.total_tokens
          assert_equal 1, @execution.total_http_calls
        end

        test "duplicate event_id returns false, does not append, and does not double-increment" do
          first = @execution.append_event(
            llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40, cached_input_tokens: 10)
          )
          dup = @execution.append_event(
            llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40, cached_input_tokens: 10)
          )
          @execution.reload

          assert_equal true,  first
          assert_equal false, dup
          assert_equal 1, @execution.events.count
          assert_equal 100_000, @execution.total_cost_micro_usd
          assert_equal 100_000, @execution.total_llm_cost_micro_usd
          assert_equal 100,     @execution.total_tokens
          assert_equal 60,      @execution.total_input_tokens
          assert_equal 40,      @execution.total_output_tokens
          assert_equal 10,      @execution.total_cached_input_tokens
        end

        test "accepts camelCase eventId alias" do
          result = @execution.append_event(
            "eventId" => "evt_camel",
            "action"  => "workflow_event.llm",
            "cost"    => { "total" => 0.05 },
            "usage"   => { "totalTokens" => 42 }
          )
          @execution.reload

          assert_equal true, result
          assert_equal 1, @execution.events.count
          assert_equal "evt_camel", @execution.events.first.event_id
          assert_equal 50_000, @execution.total_cost_micro_usd
          assert_equal 42,     @execution.total_tokens
        end

        test "missing event_id returns false immediately and does not change the row" do
          result = @execution.append_event(
            "action" => "workflow_event.llm",
            "cost"   => { "total" => 0.10 },
            "usage"  => { "totalTokens" => 100 }
          )
          @execution.reload

          assert_equal false, result
          assert_equal 0, @execution.events.count
          assert_equal 0, @execution.total_cost_micro_usd
          assert_equal 0, @execution.total_tokens
        end

        test "missing action returns false immediately and does not change the row" do
          result = @execution.append_event(
            "event_id" => "evt_noop",
            "cost"     => { "total" => 0.10 }
          )
          @execution.reload

          assert_equal false, result
          assert_equal 0, @execution.events.count
          assert_equal 0, @execution.total_cost_micro_usd
        end

        test "events of the same kind accumulate sequentially" do
          @execution.append_event(llm_event(id: "evt_a", cost: 0.10, total_tokens: 100, input_tokens: 70, output_tokens: 30))
          @execution.append_event(llm_event(id: "evt_b", cost: 0.25, total_tokens: 250, input_tokens: 150, output_tokens: 100))
          @execution.append_event(http_event(id: "evt_c"))
          @execution.append_event(http_event(id: "evt_d"))
          @execution.append_event(http_cost_event(id: "evt_e", cost: 0.01))
          @execution.reload

          assert_equal 5, @execution.events.count
          assert_equal 360_000, @execution.total_cost_micro_usd
          assert_equal 350_000, @execution.total_llm_cost_micro_usd
          assert_equal 10_000,  @execution.total_http_cost_micro_usd
          assert_equal 350,     @execution.total_tokens
          assert_equal 220,     @execution.total_input_tokens
          assert_equal 130,     @execution.total_output_tokens
          assert_equal 0,       @execution.total_cached_input_tokens
          assert_equal 2,       @execution.total_http_calls
        end

        # --- cost_payload --------------------------------------------------

        test "cost_payload returns nil when has_cost_data? is false" do
          assert_nil @execution.cost_payload
        end

        test "cost_payload reflects the rollup column values including reasoning_tokens" do
          @execution.append_event(
            llm_event(
              id: "evt_p1",
              cost: 0.40,
              total_tokens: 1_000,
              input_tokens: 700,
              output_tokens: 250,
              cached_input_tokens: 50,
              reasoning_tokens: 17
            )
          )
          @execution.append_event(http_cost_event(id: "evt_p2", cost: 0.10))
          @execution.append_event(http_event(id: "evt_p3"))
          @execution.append_event(http_event(id: "evt_p4"))

          payload = @execution.reload.cost_payload

          assert_in_delta 0.5, payload[:total_cost_usd], 1e-9
          assert_equal 2, payload[:total_http_calls]
          assert_equal({
                        input_tokens: 700,
                        output_tokens: 250,
                        cached_input_tokens: 50,
                        reasoning_tokens: 17,
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

        test "cost_payload cost_components only includes http when no llm events" do
          @execution.append_event(http_cost_event(id: "evt_h1", cost: 0.07))
          @execution.append_event(http_event(id: "evt_h2"))

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

        test "mark_completed! is state-only and does not touch cost columns" do
          @execution.append_event(llm_event(id: "evt_pre", cost: 0.10, total_tokens: 100))
          @execution.mark_completed!
          @execution.reload

          assert @execution.status_completed?
          refute_nil @execution.completed_at
          assert_equal 100_000, @execution.total_cost_micro_usd
          assert_equal 100,     @execution.total_tokens
          assert_equal 1,       @execution.events.count
        end

        private

        def llm_event(id:, cost:, total_tokens:, input_tokens: 0, output_tokens: 0, cached_input_tokens: 0, reasoning_tokens: 0, provider: nil, model_id: nil, url: nil, duration_ms: nil)
          {
            "event_id"  => id,
            "action"    => "workflow_event.llm",
            "provider"  => provider,
            "modelId"   => model_id,
            "url"       => url,
            "durationMs" => duration_ms,
            "cost"      => { "total" => cost },
            "usage"     => {
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
end
