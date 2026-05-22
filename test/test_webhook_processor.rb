# frozen_string_literal: true

require "test_helper"

class TestWebhookProcessor < Minitest::Test
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution
  WebhookProcessor  = OutputWorkflows::Rails::WebhookProcessor

  def setup
    WorkflowExecution.delete_all
  end

  def test_execution_uses_composite_lookup_when_payload_has_run_id
    target = WorkflowExecution.create!(
      workflow_id: "wf_pinned",
      workflow_run_id: "run_target",
      workflow_name: "x",
      status: "running"
    )
    # Another run for the same workflow_id — the composite lookup must NOT collapse onto this one.
    WorkflowExecution.create!(
      workflow_id: "wf_pinned",
      workflow_run_id: "run_other",
      workflow_name: "x",
      status: "running"
    )

    processor = WebhookProcessor.new("workflowId" => "wf_pinned", "runId" => "run_target")
    assert_equal target.id, processor.execution.id
  end

  def test_execution_falls_back_to_latest_run_when_payload_lacks_run_id
    WorkflowExecution.create!(
      workflow_id: "wf_legacy",
      workflow_run_id: "run_old",
      workflow_name: "x",
      status: "completed",
      created_at: 1.hour.ago
    )
    latest = WorkflowExecution.create!(
      workflow_id: "wf_legacy",
      workflow_run_id: "run_new",
      workflow_name: "x",
      status: "running",
      created_at: Time.current
    )

    processor = WebhookProcessor.new("workflowId" => "wf_legacy")
    assert_equal latest.id, processor.execution.id
  end

  def test_execution_is_nil_when_no_row_matches
    processor = WebhookProcessor.new("workflowId" => "wf_missing", "runId" => "run_missing")
    assert_nil processor.execution
  end
end
