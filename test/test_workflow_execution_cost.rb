# frozen_string_literal: true

require "test_helper"

class TestWorkflowExecutionCost < Minitest::Test
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution

  def setup
    WorkflowExecution.delete_all
    @execution = WorkflowExecution.create!(
      workflow_id: "wf_abc123",
      workflow_name: "context_persona_enrichment",
      status: "pending"
    )
  end

  def test_cost_payload_returns_nil_when_no_data
    assert_nil @execution.cost_payload
  end

  def test_cost_payload_returns_contract_shape_when_data_present
    @execution.update!(
      total_cost_micro_usd: 500_000,
      total_tokens: 1_000,
      total_http_calls: 2
    )

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
    assert_nil       payload[:trace_url]
    assert_equal [], payload[:cost_components]
  end
end
