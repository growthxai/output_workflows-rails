# frozen_string_literal: true

require "test_helper"

class TestClient < Minitest::Test
  WorkflowResult = OutputWorkflows::Responses::WorkflowResult
  WorkflowHistory = OutputWorkflows::Responses::WorkflowHistory
  WorkflowDispatch = OutputWorkflows::Responses::WorkflowDispatch

  def setup
    @client = OutputWorkflows::Client.new(api_url: "http://test.local", api_key: "test_key")
  end

  # --- start_workflow --------------------------------------------------------

  def test_start_workflow_returns_dispatch_with_workflow_and_run_ids
    body = { "workflowId" => "wf_abc", "runId" => "run_xyz" }
    stub_request(:post, "http://test.local/workflow/start")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    dispatch = @client.start_workflow("my_workflow", { foo: "bar" })

    assert_instance_of WorkflowDispatch, dispatch
    assert_equal "wf_abc", dispatch.workflow_id
    assert_equal "run_xyz", dispatch.run_id
  end

  def test_start_workflow_forwards_a_caller_supplied_workflow_id
    body = { "workflowId" => "acme-x1y2z3", "runId" => "run_xyz" }
    stub_request(:post, "http://test.local/workflow/start")
      .with(body: hash_including("workflowId" => "acme-x1y2z3"))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    dispatch = @client.start_workflow("my_workflow", { foo: "bar" }, workflow_id: "acme-x1y2z3")

    assert_equal "acme-x1y2z3", dispatch.workflow_id
  end

  def test_start_workflow_omits_workflow_id_when_not_supplied
    stub_request(:post, "http://test.local/workflow/start")
      .with { |req| !JSON.parse(req.body).key?("workflowId") }
      .to_return(status: 200, body: { "workflowId" => "wf_abc", "runId" => "run_xyz" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_equal "wf_abc", @client.start_workflow("my_workflow", { foo: "bar" }).workflow_id
  end

  def test_start_workflow_forwards_task_queue_as_camel_case
    body = { "workflowId" => "wf_abc", "runId" => "run_xyz" }
    stub_request(:post, "http://test.local/workflow/start")
      .with(body: hash_including("taskQueue" => "low"))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    @client.start_workflow("my_workflow", { foo: "bar" }, task_queue: "low")

    assert_requested :post, "http://test.local/workflow/start",
                     body: hash_including("taskQueue" => "low")
  end

  def test_start_workflow_omits_task_queue_when_not_supplied
    stub_request(:post, "http://test.local/workflow/start")
      .with { |req| !JSON.parse(req.body).key?("taskQueue") }
      .to_return(status: 200, body: { "workflowId" => "wf_abc", "runId" => "run_xyz" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_equal "wf_abc", @client.start_workflow("my_workflow", { foo: "bar" }).workflow_id
  end

  def test_start_workflow_raises_when_run_id_missing
    body = { "workflowId" => "wf_abc" }
    stub_request(:post, "http://test.local/workflow/start")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(OutputWorkflows::APIError) do
      @client.start_workflow("my_workflow", { foo: "bar" })
    end
  end

  # --- workflow_status -------------------------------------------------------

  def test_workflow_status_without_run_id_hits_unpinned_endpoint
    body = { "workflowId" => "wf_abc", "status" => "running" }
    stub_request(:get, "http://test.local/workflow/wf_abc/status")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    status = @client.workflow_status("wf_abc")

    assert status.running?
    assert_requested :get, "http://test.local/workflow/wf_abc/status"
  end

  def test_workflow_status_with_run_id_hits_run_scoped_endpoint
    body = { "workflowId" => "wf_abc", "status" => "completed" }
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/status")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    @client.workflow_status("wf_abc", run_id: "run_xyz")

    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/status"
  end

  # --- cancel_workflow -------------------------------------------------------

  def test_cancel_workflow_without_run_id_hits_unpinned_endpoint
    stub_request(:patch, "http://test.local/workflow/wf_abc/stop")
      .to_return(status: 200, body: "", headers: { "Content-Type" => "application/json" })

    assert @client.cancel_workflow("wf_abc")
    assert_requested :patch, "http://test.local/workflow/wf_abc/stop"
  end

  def test_cancel_workflow_with_run_id_hits_run_scoped_endpoint
    stub_request(:patch, "http://test.local/workflow/wf_abc/runs/run_xyz/stop")
      .to_return(status: 200, body: "", headers: { "Content-Type" => "application/json" })

    assert @client.cancel_workflow("wf_abc", run_id: "run_xyz")
    assert_requested :patch, "http://test.local/workflow/wf_abc/runs/run_xyz/stop"
  end

  # A stop that the API rejects with a non-gone 4xx (e.g. 400 for a legacy run)
  # must surface as a wrapped APIError, not a raw Faraday error — otherwise
  # WorkflowExecution#cancel! can't rescue it and the dispatch job crashes.
  def test_cancel_workflow_wraps_unexpected_4xx_as_api_error
    stub_request(:patch, "http://test.local/workflow/wf_abc/runs/legacy-123/stop")
      .to_return(status: 400, body: '{"error":"cannot stop run"}',
                 headers: { "Content-Type" => "application/json" })

    assert_raises(OutputWorkflows::APIError) do
      @client.cancel_workflow("wf_abc", run_id: "legacy-123")
    end
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

  # --- workflow_history ------------------------------------------------------

  def test_workflow_history_without_run_id_hits_unpinned_endpoint
    body = {
      "workflow" => { "workflowId" => "wf_abc", "runId" => "run_xyz", "status" => "RUNNING" },
      "events" => [{ "eventId" => "1", "eventTypeName" => "WORKFLOW_EXECUTION_STARTED" }],
      "nextPageToken" => nil
    }
    stub_request(:get, "http://test.local/workflow/wf_abc/history")
      .with(query: { "pageSize" => "50", "includePayloads" => "false" })
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    history = @client.workflow_history("wf_abc")

    assert_instance_of WorkflowHistory, history
    assert_equal "run_xyz", history.run_id
    assert_equal 1, history.events.size
    assert_nil history.next_page_token
  end

  def test_workflow_history_with_run_id_hits_run_scoped_endpoint
    body = { "workflow" => { "workflowId" => "wf_abc", "runId" => "run_xyz" }, "events" => [] }
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/history")
      .with(query: { "pageSize" => "50", "includePayloads" => "false" })
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    @client.workflow_history("wf_abc", run_id: "run_xyz")

    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/history",
                     query: { "pageSize" => "50", "includePayloads" => "false" }
  end

  def test_workflow_history_plumbs_include_payloads_and_page_size
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/history")
      .with(query: { "pageSize" => "10", "includePayloads" => "true" })
      .to_return(status: 200, body: { "workflow" => nil, "events" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    @client.workflow_history("wf_abc", run_id: "run_xyz", page_size: 10, include_payloads: true)

    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/history",
                     query: { "pageSize" => "10", "includePayloads" => "true" }
  end

  def test_workflow_history_passes_page_token_when_given
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/history")
      .with(query: { "pageSize" => "50", "includePayloads" => "false", "pageToken" => "next_cursor" })
      .to_return(status: 200, body: { "workflow" => nil, "events" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    @client.workflow_history("wf_abc", run_id: "run_xyz", page_token: "next_cursor")

    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/history",
                     query: { "pageSize" => "50", "includePayloads" => "false", "pageToken" => "next_cursor" }
  end

  def test_workflow_history_omits_page_token_when_nil
    stub_request(:get, "http://test.local/workflow/wf_abc/history")
      .with(query: { "pageSize" => "50", "includePayloads" => "false" })
      .to_return(status: 200, body: { "events" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    @client.workflow_history("wf_abc", page_token: nil)

    assert_requested :get, "http://test.local/workflow/wf_abc/history",
                     query: { "pageSize" => "50", "includePayloads" => "false" }
  end

  def test_workflow_history_raises_api_error_on_5xx
    stub_request(:get, "http://test.local/workflow/wf_abc/history")
      .with(query: hash_including({}))
      .to_return(status: 500, body: '{"error":"upstream timeout"}',
                 headers: { "Content-Type" => "application/json" })

    assert_raises(OutputWorkflows::APIError) do
      @client.workflow_history("wf_abc")
    end
  end

  # --- wait_for_completion ---------------------------------------------------

  def test_wait_for_completion_passes_run_id_through_to_status_and_result_calls
    status_body = { "workflowId" => "wf_abc", "status" => "completed", "statusName" => "COMPLETED" }
    result_body = { "workflowId" => "wf_abc", "output" => { "ok" => true } }

    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/status")
      .to_return(status: 200, body: status_body.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "http://test.local/workflow/wf_abc/runs/run_xyz/result")
      .to_return(status: 200, body: result_body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.wait_for_completion("wf_abc", poll_interval: 0.01, timeout: 5, run_id: "run_xyz")

    assert_instance_of WorkflowResult, result
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/status"
    assert_requested :get, "http://test.local/workflow/wf_abc/runs/run_xyz/result"
  end
end
