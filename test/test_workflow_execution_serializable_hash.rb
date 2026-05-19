# frozen_string_literal: true

require "test_helper"

class TestWorkflowExecutionSerializableHash < Minitest::Test
  WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution
  WorkflowResult    = OutputWorkflows::Responses::WorkflowResult

  def setup
    WorkflowExecution.delete_all
    @execution = WorkflowExecution.create!(
      workflow_id: "wf_serialize",
      workflow_name: "context_persona_enrichment",
      status: "running"
    )
  end

  def test_omits_cost_when_no_rollup_data
    refute_includes @execution.serializable_hash.keys, "cost"
  end

  def test_includes_cost_block_when_rollup_data_present
    result = WorkflowResult.new(
      workflow_id: @execution.workflow_id,
      output: {},
      trace: {},
      aggregations: {
        "cost"         => { "total" => 0.1 },
        "tokens"       => { "total" => 7 },
        "httpRequests" => { "total" => 0 }
      },
      attributes: []
    )
    @execution.apply_workflow_result!(result)

    hash = @execution.reload.serializable_hash
    assert_includes hash.keys, "cost"
    assert_in_delta 0.1, hash["cost"][:total_cost_usd], 1e-9
    assert_equal 7, hash["cost"][:token_usage]["total_tokens"]
  end
end
