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

        teardown do
          OutputWorkflows.configuration.event_retention = nil
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

        test "append_event never writes the executions row (lock-convoy regression)" do
          @execution.mark_running!

          updates = []
          subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            updates << payload[:sql] if payload[:sql] =~ /UPDATE\s+"?output_workflow_executions"?/i
          end

          @execution.append_event(llm_event(id: "evt_lock", cost: 0.10, total_tokens: 100))
          @execution.append_event(http_event(id: "evt_lock2"))

          assert_empty updates
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
        end

        test "append_event leaves all rollup columns at 0" do
          @execution.append_event(
            llm_event(id: "evt_1", cost: 0.123456, total_tokens: 1_234, input_tokens: 800, output_tokens: 400)
          )
          @execution.append_event(http_event(id: "evt_2"))
          @execution.reload

          Cost::ROLLUP_AGGREGATES.each_key do |column|
            assert_equal 0, @execution[column], "expected #{column} to stay 0 until terminal recompute"
          end
          assert_nil @execution.rollups_computed_at
        end

        test "http_cost event appends one events entry with cost only" do
          result = @execution.append_event(http_cost_event(id: "evt_h", cost: 0.05))
          @execution.reload

          assert_equal true, result
          assert_equal 1, @execution.events.count

          entry = @execution.events.first
          assert_equal "evt_h",     entry.event_id
          assert_equal "http_cost", entry.action_type
          assert_equal 50_000,      entry.cost_micro_usd
          assert_equal 0,           entry.total_tokens
        end

        test "http action_type records cost_micro_usd: 0 on the event row even when payload has cost" do
          result = @execution.append_event(
            "event_id" => "evt_http_cost",
            "action" => "workflow_event.http",
            "cost" => { "total" => 0.001 },
            "url" => "https://api.example.com/things"
          )
          @execution.mark_completed!
          @execution.reload

          assert_equal true, result
          entry = @execution.events.first
          assert_equal 0, entry.cost_micro_usd
          assert_equal 0, @execution.total_cost_micro_usd
          assert_equal 1, @execution.total_http_calls
        end

        test "duplicate event_id returns false, does not append, and does not double-count" do
          first = @execution.append_event(
            llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40,
                      cached_input_tokens: 10)
          )
          dup = @execution.append_event(
            llm_event(id: "evt_dup", cost: 0.10, total_tokens: 100, input_tokens: 60, output_tokens: 40,
                      cached_input_tokens: 10)
          )
          @execution.mark_completed!
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
            "action" => "workflow_event.llm",
            "cost" => { "total" => 0.05 },
            "usage" => { "totalTokens" => 42 }
          )

          assert_equal true, result
          assert_equal 1, @execution.events.count
          assert_equal "evt_camel", @execution.events.first.event_id

          payload = @execution.cost_payload
          assert_in_delta 0.05, payload[:total_cost_usd], 1e-9
          assert_equal 42, payload[:token_usage][:total_tokens]
        end

        test "missing event_id returns false immediately and does not change the row" do
          result = @execution.append_event(
            "action" => "workflow_event.llm",
            "cost" => { "total" => 0.10 },
            "usage" => { "totalTokens" => 100 }
          )
          @execution.reload

          assert_equal false, result
          assert_equal 0, @execution.events.count
        end

        test "missing action returns false immediately and does not change the row" do
          result = @execution.append_event(
            "event_id" => "evt_noop",
            "cost" => { "total" => 0.10 }
          )
          @execution.reload

          assert_equal false, result
          assert_equal 0, @execution.events.count
        end

        # --- cost_payload --------------------------------------------------

        test "cost_payload returns nil when there is no cost data" do
          assert_nil @execution.cost_payload
        end

        test "cost_payload derives live from events for active executions" do
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

          assert_equal 0, @execution.total_cost_micro_usd, "columns must stay untouched while active"
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
          assert_equal(
            [{ name: "http:request:cost", value_cents: 7 }],
            payload[:cost_components]
          )
        end

        test "cost_payload reads persisted columns for terminal executions even when events disagree" do
          @execution.append_event(http_event(id: "evt_stale"))
          @execution.mark_completed!
          @execution.update_columns(total_cost_micro_usd: 999_000, total_http_calls: 7)

          payload = @execution.reload.cost_payload

          assert_in_delta 0.999, payload[:total_cost_usd], 1e-9
          assert_equal 7, payload[:total_http_calls]
        end

        test "serializable_hash includes derived cost for an active execution" do
          @execution.append_event(http_event(id: "evt_s1"))

          hash = @execution.serializable_hash

          assert_equal 1, hash["cost"][:total_http_calls]
        end

        # --- recompute_rollups ---------------------------------------------

        test "mark_completed! recomputes all rollup columns from events" do
          @execution.append_event(llm_event(id: "evt_a", cost: 0.10, total_tokens: 100, input_tokens: 70,
                                            output_tokens: 30))
          @execution.append_event(llm_event(id: "evt_b", cost: 0.25, total_tokens: 250, input_tokens: 150,
                                            output_tokens: 100))
          @execution.append_event(http_event(id: "evt_c"))
          @execution.append_event(http_event(id: "evt_d"))
          @execution.append_event(http_cost_event(id: "evt_e", cost: 0.01))

          @execution.mark_completed!
          @execution.reload

          assert_equal 360_000, @execution.total_cost_micro_usd
          assert_equal 350_000, @execution.total_llm_cost_micro_usd
          assert_equal 10_000,  @execution.total_http_cost_micro_usd
          assert_equal 350,     @execution.total_tokens
          assert_equal 220,     @execution.total_input_tokens
          assert_equal 130,     @execution.total_output_tokens
          assert_equal 0,       @execution.total_cached_input_tokens
          assert_equal 0,       @execution.total_reasoning_tokens
          assert_equal 2,       @execution.total_http_calls
          refute_nil @execution.rollups_computed_at
        end

        test "mark_failed! recomputes rollups" do
          @execution.append_event(http_event(id: "evt_f1"))
          @execution.mark_failed!("boom")
          @execution.reload

          assert_equal 1, @execution.total_http_calls
          refute_nil @execution.rollups_computed_at
        end

        test "cancel! recomputes rollups via mark_failed!" do
          stub_request(:patch, %r{/stop})
          @execution.append_event(http_event(id: "evt_cxl"))

          @execution.cancel!
          @execution.reload

          assert @execution.status_failed?
          assert_equal 1, @execution.total_http_calls
          refute_nil @execution.rollups_computed_at
        end

        test "recompute_rollups is absolute and idempotent" do
          @execution.append_event(http_event(id: "evt_i1"))
          @execution.mark_completed!
          @execution.update_columns(total_http_calls: 999, total_cost_micro_usd: 123)

          @execution.recompute_rollups
          first_pass = @execution.reload.attributes.slice(*Cost::ROLLUP_AGGREGATES.keys.map(&:to_s))

          @execution.recompute_rollups
          second_pass = @execution.reload.attributes.slice(*Cost::ROLLUP_AGGREGATES.keys.map(&:to_s))

          assert_equal 1, @execution.total_http_calls
          assert_equal 0, @execution.total_cost_micro_usd
          assert_equal first_pass, second_pass
        end

        test "recompute only fires on a terminal transition" do
          @execution.append_event(http_event(id: "evt_g1"))

          @execution.mark_running!
          assert_nil @execution.reload.rollups_computed_at

          @execution.mark_completed!
          watermark = @execution.reload.rollups_computed_at
          refute_nil watermark

          @execution.update!(error_message: "post-terminal note")
          assert_equal watermark, @execution.reload.rollups_computed_at
        end

        test "recompute_rollups does not bump updated_at" do
          @execution.append_event(http_event(id: "evt_u1"))
          @execution.mark_completed!
          @execution.reload
          before = @execution.updated_at

          @execution.recompute_rollups

          assert_equal before, @execution.reload.updated_at
          refute_nil @execution.rollups_computed_at
        end

        test "recompute_rollups is a no-op when an old execution's events aged past retention" do
          OutputWorkflows.configuration.event_retention = 14.days
          @execution.append_event(http_event(id: "evt_r1"))
          @execution.events.update_all(created_at: 20.days.ago)
          @execution.update_columns(created_at: 20.days.ago, total_http_calls: 42)

          @execution.mark_completed!
          @execution.reload

          assert @execution.status_completed?
          assert_equal 42, @execution.total_http_calls, "totals must not be overwritten past retention"
          assert_nil @execution.rollups_computed_at
        end

        test "recompute_rollups is a no-op for an old execution with no surviving events" do
          OutputWorkflows.configuration.event_retention = 14.days
          @execution.update_columns(created_at: 20.days.ago, total_http_calls: 42)

          @execution.mark_completed!
          @execution.reload

          assert_equal 42, @execution.total_http_calls, "no events is indistinguishable from fully purged"
          assert_nil @execution.rollups_computed_at
        end

        test "recompute_rollups still runs for an old execution whose events are inside retention" do
          OutputWorkflows.configuration.event_retention = 14.days
          @execution.append_event(http_event(id: "evt_r2"))
          @execution.update_columns(created_at: 20.days.ago, total_http_calls: 42)

          @execution.mark_completed!
          @execution.reload

          assert_equal 1, @execution.total_http_calls, "surviving events are the same truth derive-on-read showed live"
          refute_nil @execution.rollups_computed_at
        end

        test "recompute_rollups runs without retention configured" do
          OutputWorkflows.configuration.event_retention = nil
          @execution.append_event(http_event(id: "evt_r2"))
          @execution.update_columns(created_at: 400.days.ago)

          @execution.mark_completed!

          assert_equal 1, @execution.reload.total_http_calls
        end

        test "rollups_stale matches NULL watermarks and events past the coverage guarantee" do
          @execution.append_event(http_event(id: "evt-s1"))
          assert_includes WorkflowExecution.rollups_stale, @execution

          @execution.mark_completed!
          # The last event landed within COVERAGE_MARGIN of the watermark, so
          # coverage isn't guaranteed yet: still stale until a later recompute.
          assert_includes WorkflowExecution.rollups_stale, @execution

          travel 2.minutes do
            @execution.recompute_rollups
            refute_includes WorkflowExecution.rollups_stale, @execution

            @execution.append_event(http_event(id: "evt-s2"))
            assert_includes WorkflowExecution.rollups_stale, @execution
          end
        end

        test "zero-event completion leaves columns at 0 and cost_payload nil" do
          @execution.mark_completed!
          @execution.reload

          Cost::ROLLUP_AGGREGATES.each_key { |column| assert_equal 0, @execution[column] }
          refute_nil @execution.rollups_computed_at
          assert_nil @execution.cost_payload
        end

        private

        def llm_event(id:, cost:, total_tokens:, input_tokens: 0, output_tokens: 0, cached_input_tokens: 0,
                      reasoning_tokens: 0, provider: nil, model_id: nil, url: nil, duration_ms: nil)
          {
            "event_id" => id,
            "action" => "workflow_event.llm",
            "provider" => provider,
            "modelId" => model_id,
            "url" => url,
            "durationMs" => duration_ms,
            "cost" => { "total" => cost },
            "usage" => {
              "totalTokens" => total_tokens,
              "inputTokens" => input_tokens,
              "outputTokens" => output_tokens,
              "cachedInputTokens" => cached_input_tokens,
              "reasoningTokens" => reasoning_tokens
            }
          }
        end

        def http_cost_event(id:, cost:)
          {
            "event_id" => id,
            "action" => "workflow_event.http_cost",
            "cost" => { "total" => cost }
          }
        end

        def http_event(id:)
          {
            "event_id" => id,
            "action" => "workflow_event.http"
          }
        end
      end
    end
  end
end
