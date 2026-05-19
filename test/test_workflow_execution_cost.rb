# frozen_string_literal: true

require "test_helper"

class TestWorkflowExecutionCost < Minitest::Test
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution

  def setup
    WorkflowExecution::RollupEvent.delete_all
    WorkflowExecution.delete_all
    @execution = WorkflowExecution.create!(
      workflow_id: "wf_abc123",
      workflow_name: "context_persona_enrichment",
      status: "pending"
    )
  end

  def test_apply_llm_event_increments_cost_and_tokens
    payload = {
      action: "workflow_event.llm",
      event_id: "evt_1",
      workflowId: @execution.workflow_id,
      cost: { total: 0.123456 },
      usage: { totalTokens: 1_234 },
      modelId: "claude-opus-4-7"
    }

    assert @execution.apply_cost_event!(payload)
    @execution.reload

    assert_equal 123_456, @execution.total_cost_micro_usd
    assert_equal 1_234,   @execution.total_tokens
    assert_equal 0,       @execution.total_http_calls
  end

  def test_apply_http_cost_event_increments_only_cost
    payload = {
      action: "workflow_event.http_cost",
      event_id: "evt_2",
      cost: { total: 0.05 },
      url: "https://api.firecrawl.dev/scrape"
    }

    assert @execution.apply_cost_event!(payload)
    @execution.reload

    assert_equal 50_000, @execution.total_cost_micro_usd
    assert_equal 0,      @execution.total_tokens
    assert_equal 0,      @execution.total_http_calls
  end

  def test_apply_http_event_increments_http_calls
    payload = {
      action: "workflow_event.http",
      event_id: "evt_3",
      method: "GET",
      url: "https://example.com",
      status: 200,
      durationMs: 120,
      outcome: "ok"
    }

    assert @execution.apply_cost_event!(payload)
    @execution.reload

    assert_equal 0, @execution.total_cost_micro_usd
    assert_equal 0, @execution.total_tokens
    assert_equal 1, @execution.total_http_calls
  end

  def test_apply_cost_event_is_idempotent_on_same_event_id
    payload = {
      action: "workflow_event.llm",
      event_id: "evt_dup",
      cost: { total: 1.0 },
      usage: { totalTokens: 100 }
    }

    assert @execution.apply_cost_event!(payload)
    refute @execution.apply_cost_event!(payload), "second call should report no-op"

    @execution.reload
    assert_equal 1_000_000, @execution.total_cost_micro_usd
    assert_equal 100,       @execution.total_tokens
    assert_equal 1,         WorkflowExecution::RollupEvent.where(workflow_execution_id: @execution.id).count
  end

  def test_apply_cost_event_with_missing_event_id_returns_false
    payload = { action: "workflow_event.llm", cost: { total: 1.0 }, usage: { totalTokens: 1 } }

    refute @execution.apply_cost_event!(payload)
    @execution.reload
    assert_equal 0, @execution.total_cost_micro_usd
  end

  def test_apply_cost_event_with_missing_action_returns_false
    payload = { event_id: "evt_x", cost: { total: 1.0 } }

    refute @execution.apply_cost_event!(payload)
  end

  def test_apply_cost_event_with_unknown_action_records_dedup_but_does_not_increment
    payload = { action: "workflow_event.unknown", event_id: "evt_q" }

    assert @execution.apply_cost_event!(payload)
    @execution.reload
    assert_equal 0, @execution.total_cost_micro_usd
    assert_equal 0, @execution.total_tokens
    assert_equal 0, @execution.total_http_calls
  end

  def test_apply_cost_event_accepts_string_keyed_payload
    payload = {
      "action" => "workflow_event.llm",
      "event_id" => "evt_strkeys",
      "cost" => { "total" => 0.25 },
      "usage" => { "totalTokens" => 500 }
    }

    assert @execution.apply_cost_event!(payload)
    @execution.reload

    assert_equal 250_000, @execution.total_cost_micro_usd
    assert_equal 500,     @execution.total_tokens
  end

  def test_cost_payload_returns_nil_when_no_data
    assert_nil @execution.cost_payload
  end

  def test_cost_payload_returns_contract_shape_when_data_present
    @execution.apply_cost_event!(
      action: "workflow_event.llm",
      event_id: "evt_a",
      cost: { total: 0.5 },
      usage: { totalTokens: 1_000 }
    )
    @execution.apply_cost_event!(action: "workflow_event.http", event_id: "evt_b")
    @execution.apply_cost_event!(action: "workflow_event.http", event_id: "evt_c")

    payload = @execution.reload.cost_payload

    assert_in_delta 0.5, payload[:total_cost_usd], 1e-9
    assert_equal 2,    payload[:total_http_calls]
    assert_nil         payload[:runtime_ms]
    assert_equal({
                   "input_tokens" => 0,
                   "output_tokens" => 0,
                   "cached_input_tokens" => 0,
                   "total_tokens" => 1_000
                 }, payload[:token_usage])
    assert_nil payload[:trace_url]
    assert_equal [], payload[:cost_components]
  end

  def test_cost_payload_returns_trace_url_and_components_from_cost_data
    @execution.update!(
      cost_data: {
        "trace_url" => "https://s3.example/trace.json",
        "cost_components" => [{ "name" => "cost:llm:request", "value" => 0.3 }]
      }
    )
    @execution.apply_cost_event!(
      action: "workflow_event.llm",
      event_id: "evt_seed",
      cost: { total: 0.3 },
      usage: { totalTokens: 1 }
    )

    payload = @execution.reload.cost_payload
    assert_equal "https://s3.example/trace.json", payload[:trace_url]
    assert_equal [{ "name" => "cost:llm:request", "value" => 0.3 }], payload[:cost_components]
  end

end
