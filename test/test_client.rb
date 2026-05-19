# frozen_string_literal: true

require "test_helper"

class TestClient < Minitest::Test
  WorkflowResult = OutputWorkflows::Responses::WorkflowResult

  def setup
    @client = OutputWorkflows::Client.new(api_url: "http://test.local", api_key: "test_key")
  end

  # --- workflow_result -------------------------------------------------------

  def test_workflow_result_without_run_id_hits_unpinned_endpoint
    body = { "workflowId" => "wf_abc", "output" => { "foo" => "bar" } }
    stub_request(:get, "http://test.local/workflow/wf_abc/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.workflow_result("wf_abc")

    assert_instance_of WorkflowResult, result
    assert_equal "wf_abc", result.workflow_id
    assert_equal({ "foo" => "bar" }, result.output)
    assert_requested :get, "http://test.local/workflow/wf_abc/result"
  end

  def test_workflow_result_with_run_id_hits_run_scoped_endpoint
    body = { "workflowId" => "wf_abc", "output" => { "foo" => "bar" } }
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.workflow_result("wf_abc", run_id: "run_xyz")

    assert_instance_of WorkflowResult, result
    assert_equal "wf_abc", result.workflow_id
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end

  def test_workflow_result_with_nil_run_id_falls_back_to_unpinned_endpoint
    body = { "workflowId" => "wf_abc" }
    stub_request(:get, "http://test.local/workflow/wf_abc/result")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    @client.workflow_result("wf_abc", run_id: nil)

    assert_requested :get, "http://test.local/workflow/wf_abc/result"
  end

  # --- wait_for_completion ---------------------------------------------------

  def test_wait_for_completion_passes_run_id_through_to_result_call
    status_body = { "workflowId" => "wf_abc", "status" => "completed", "statusName" => "COMPLETED" }
    result_body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }

    stub_request(:get, "http://test.local/workflow/wf_abc/status")
      .to_return(status: 200, body: status_body.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: result_body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.wait_for_completion("wf_abc", poll_interval: 0.01, timeout: 5, run_id: "run_xyz")

    assert_instance_of WorkflowResult, result
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end
end
