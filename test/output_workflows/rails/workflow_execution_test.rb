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
          workflow_run_id: "run_serialize",
          workflow_name: "context_persona_enrichment",
          status: "running"
        )

      end

      test "composite uniqueness: same workflow_id + different run_id is allowed" do
        WorkflowExecution.create!(workflow_id: "wf_can", workflow_run_id: "run_a", workflow_name: "x")
        second = WorkflowExecution.new(workflow_id: "wf_can", workflow_run_id: "run_b", workflow_name: "x")
        assert second.valid?, second.errors.full_messages.inspect
      end

      test "composite uniqueness: same workflow_id + same run_id is rejected" do
        WorkflowExecution.create!(workflow_id: "wf_dup", workflow_run_id: "run_dup", workflow_name: "x")
        dupe = WorkflowExecution.new(workflow_id: "wf_dup", workflow_run_id: "run_dup", workflow_name: "x")
        refute dupe.valid?
        assert_includes dupe.errors[:workflow_id], "has already been taken"
      end

      test "find_by_workflow_run! resolves by composite key" do
        target = WorkflowExecution.create!(workflow_id: "wf_lookup", workflow_run_id: "run_lookup", workflow_name: "x")
        WorkflowExecution.create!(workflow_id: "wf_lookup", workflow_run_id: "run_other", workflow_name: "x")

        found = WorkflowExecution.find_by_workflow_run!(workflow_id: "wf_lookup", run_id: "run_lookup")
        assert_equal target.id, found.id

        assert_raises(ActiveRecord::RecordNotFound) do
          WorkflowExecution.find_by_workflow_run!(workflow_id: "wf_lookup", run_id: "run_missing")
        end
      end

      test "omits cost when no rollup data" do
        refute_includes @execution.serializable_hash.keys, "cost"
      end

      test "includes cost block when rollup data present" do
        @execution.append_event(
          "event_id" => "evt_ser",
          "action"   => "workflow_event.llm",
          "cost"     => { "total" => 0.1 },
          "usage"    => { "totalTokens" => 7 }
        )

        hash = @execution.reload.serializable_hash
        assert_includes hash.keys, "cost"
        assert_in_delta 0.1, hash["cost"][:total_cost_usd], 1e-9
        assert_equal 7, hash["cost"][:token_usage][:total_tokens]
      end

      test "mark_completed! does not clobber a prior failed state" do
        @execution.mark_failed!("boom")
        assert_equal "failed", @execution.status
        assert_equal "boom",   @execution.error_message

        @execution.mark_completed!

        assert_equal "failed", @execution.status,        "status was flipped from failed to completed"
        assert_equal "boom",   @execution.error_message, "error_message was clobbered"
      end
    end
  end
end
