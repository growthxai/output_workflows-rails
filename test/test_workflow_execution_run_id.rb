# frozen_string_literal: true

require "test_helper"

class TestWorkflowExecutionRunId < Minitest::Test
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution

  def setup
    WorkflowExecution.delete_all
    @execution = WorkflowExecution.create!(
      workflow_id: "wf_abc",
      workflow_name: "context_persona_enrichment",
      status: "pending"
    )
  end

  # --- fetch_result! ---------------------------------------------------------

  def test_fetch_result_without_run_id_hits_unpinned_endpoint
    body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }
    stub_request(:get, "http://test.local/workflow/wf_abc/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @execution.fetch_result!

    assert_equal "wf_abc", result.workflow_id
    assert_requested :get, "http://test.local/workflow/wf_abc/result"
  end

  def test_fetch_result_with_run_id_hits_run_scoped_endpoint
    body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    @execution.fetch_result!(run_id: "run_xyz")

    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end

  # --- fetch_output! ---------------------------------------------------------

  def test_fetch_output_with_run_id_hits_run_scoped_endpoint
    body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    output = @execution.fetch_output!(run_id: "run_xyz")

    assert_equal({ "ok" => true }, output)
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end

  # --- poll_status! ----------------------------------------------------------

  def test_poll_status_with_run_id_fetches_run_scoped_result_on_completion
    status_body = { "workflowId" => "wf_abc", "status" => "completed", "statusName" => "COMPLETED" }
    result_body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }

    stub_request(:get, "http://test.local/workflow/wf_abc/status")
      .to_return(status: 200, body: status_body.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: result_body.to_json, headers: { "Content-Type" => "application/json" })

    assert @execution.poll_status!(run_id: "run_xyz")
    @execution.reload
    assert @execution.status_completed?
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end

  # --- wait_for_completion! --------------------------------------------------

  def test_wait_for_completion_with_run_id_fetches_run_scoped_result
    status_body = { "workflowId" => "wf_abc", "status" => "completed", "statusName" => "COMPLETED" }
    result_body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }

    stub_request(:get, "http://test.local/workflow/wf_abc/status")
      .to_return(status: 200, body: status_body.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: result_body.to_json, headers: { "Content-Type" => "application/json" })

    result = @execution.wait_for_completion!(poll_interval: 0.01, timeout: 5, run_id: "run_xyz")

    assert_equal "wf_abc", result.workflow_id
    @execution.reload
    assert @execution.status_completed?
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end
end
