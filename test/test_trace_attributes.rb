# frozen_string_literal: true

require "test_helper"

class TestTraceAttributes < Minitest::Test
  WORKFLOW_ID = "wf_abc123"
  RUN_ID      = "01HX0000000000000000000000"

  def setup
    @client = OutputWorkflows::Client.new(api_url: "http://test.local")
  end

  # Canonical response shape from overview.md §1.1
  def trace_attributes_body(workflow_id: WORKFLOW_ID, run_id: RUN_ID)
    {
      "workflowId" => workflow_id,
      "runId" => run_id,
      "startTime" => 1_715_567_000_000,
      "finishTime" => 1_715_567_027_341,
      "runtime" => 27_341,
      "attributes" => {
        "cost" => {
          "total" => 0.4231,
          "components" => [
            { "name" => "cost:llm:request",  "value" => 0.3829 },
            { "name" => "cost:http:request", "value" => 0.0402 },
            { "name" => "other",             "value" => 0.0000 }
          ]
        },
        "tokenUsage" => {
          "inputTokens" => 14_322,
          "outputTokens" => 2_841,
          "cachedInputTokens" => 800,
          "totalTokens" => 17_963
        }
      },
      "traceUrl" => "https://s3.example/trace.json"
    }
  end

  def test_trace_attributes_latest_run_returns_parsed_hash
    body = trace_attributes_body
    stub_request(:get, "http://test.local/workflow/#{WORKFLOW_ID}/trace-attributes")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.trace_attributes(WORKFLOW_ID)

    assert_equal body, result
    assert_equal 0.4231, result.dig("attributes", "cost", "total")
    assert_equal 17_963, result.dig("attributes", "tokenUsage", "totalTokens")
  end

  def test_trace_attributes_pinned_run_hits_pinned_path
    body = trace_attributes_body
    stub_request(:get, "http://test.local/workflow/#{WORKFLOW_ID}/runs/#{RUN_ID}/trace-attributes")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.trace_attributes(WORKFLOW_ID, run_id: RUN_ID)

    assert_equal RUN_ID, result["runId"]
    assert_requested(
      :get,
      "http://test.local/workflow/#{WORKFLOW_ID}/runs/#{RUN_ID}/trace-attributes"
    )
  end

  def test_trace_attributes_raises_workflow_not_completed_on_424
    stub_request(:get, "http://test.local/workflow/#{WORKFLOW_ID}/trace-attributes")
      .to_return(
        status: 424,
        body: { "error" => "workflow not completed" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(OutputWorkflows::WorkflowNotCompletedError) do
      @client.trace_attributes(WORKFLOW_ID)
    end

    assert_match(/#{WORKFLOW_ID}/, error.message)
  end

  def test_trace_attributes_raises_workflow_not_found_on_404
    stub_request(:get, "http://test.local/workflow/#{WORKFLOW_ID}/trace-attributes")
      .to_return(status: 404, body: "not found")

    error = assert_raises(OutputWorkflows::WorkflowNotFoundError) do
      @client.trace_attributes(WORKFLOW_ID)
    end

    assert_match(/#{WORKFLOW_ID}/, error.message)
  end

  def test_trace_attributes_raises_server_error_on_5xx
    stub_request(:get, "http://test.local/workflow/#{WORKFLOW_ID}/trace-attributes")
      .to_return(status: 503, body: "server down")

    error = assert_raises(OutputWorkflows::ServerError) do
      @client.trace_attributes(WORKFLOW_ID)
    end

    assert_equal 503, error.response_status
  end

  def test_server_error_is_an_api_error
    # Allows existing rescue OutputWorkflows::APIError code paths to keep working.
    assert_operator OutputWorkflows::ServerError, :<, OutputWorkflows::APIError
  end

  def test_workflow_not_completed_is_an_error
    assert_operator OutputWorkflows::WorkflowNotCompletedError, :<, OutputWorkflows::Error
  end
end
