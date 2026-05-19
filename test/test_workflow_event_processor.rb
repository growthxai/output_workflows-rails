# frozen_string_literal: true

require "test_helper"

class TestWorkflowEventProcessor < Minitest::Test
  Processor = OutputWorkflows::Rails::WorkflowEventProcessor
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution

  def setup
    WorkflowExecution::RollupEvent.delete_all
    WorkflowExecution.delete_all
    @execution = WorkflowExecution.create!(
      workflow_id: "wf_proc",
      workflow_name: "context_persona_enrichment",
      status: "running"
    )
  end

  def test_process_dispatches_to_apply_cost_event
    payload = {
      action: "workflow_event.llm",
      workflowId: @execution.workflow_id,
      event_id: "evt_p1",
      cost: { total: 0.2 },
      usage: { totalTokens: 250 }
    }

    result = Processor.new(payload).process

    assert_equal @execution.id, result.id
    @execution.reload
    assert_equal 200_000, @execution.total_cost_micro_usd
    assert_equal 250,     @execution.total_tokens
  end

  def test_process_returns_nil_when_workflow_id_unknown
    payload = {
      action: "workflow_event.llm",
      workflowId: "wf_does_not_exist",
      event_id: "evt_orphan",
      cost: { total: 1.0 },
      usage: { totalTokens: 1 }
    }

    assert_nil Processor.new(payload).process
  end

  def test_process_is_idempotent
    payload = {
      action: "workflow_event.http",
      workflowId: @execution.workflow_id,
      event_id: "evt_http_1",
      method: "GET",
      url: "https://example.com",
      status: 200,
      durationMs: 50,
      outcome: "ok"
    }

    Processor.new(payload).process
    Processor.new(payload).process

    @execution.reload
    assert_equal 1, @execution.total_http_calls
  end

  def test_process_accepts_json_string_payload
    payload = {
      action: "workflow_event.llm",
      workflowId: @execution.workflow_id,
      event_id: "evt_json",
      cost: { total: 0.04 },
      usage: { totalTokens: 12 }
    }.to_json

    Processor.new(payload).process

    @execution.reload
    assert_equal 40_000, @execution.total_cost_micro_usd
    assert_equal 12,     @execution.total_tokens
  end
end
