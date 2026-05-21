# frozen_string_literal: true

require "test_helper"
require "active_support/test_case"

module OutputWorkflows
  module Rails
    class WorkflowExecutionTest < ActiveSupport::TestCase
      WorkflowExecution = OutputWorkflows::Rails::WorkflowExecution
      WorkflowResult    = OutputWorkflows::Responses::WorkflowResult

      setup do
        WorkflowExecution.delete_all
        @execution = WorkflowExecution.create!(
          workflow_id: "wf_serialize",
          workflow_name: "context_persona_enrichment",
          status: "running"
        )
      end

      test "omits cost when no rollup data" do
        refute_includes @execution.serializable_hash.keys, "cost"
      end

      test "includes cost block when rollup data present" do
        result = WorkflowResult.new(
          workflow_id: @execution.workflow_id,
          output: {},
          trace: {},
          aggregations: {
            "cost" => { "total" => 0.1 },
            "tokens" => { "total" => 7 },
            "httpRequests" => { "total" => 0 }
          },
          attributes: []
        )
        @execution.apply_workflow_result(result)

        hash = @execution.reload.serializable_hash
        assert_includes hash.keys, "cost"
        assert_in_delta 0.1, hash["cost"][:total_cost_usd], 1e-9
        assert_equal 7, hash["cost"][:token_usage][:total_tokens]
      end
    end
  end
end
