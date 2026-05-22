# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class WorkflowDispatch
      attr_reader :workflow_id, :run_id

      def initialize(workflow_id:, run_id:)
        @workflow_id = workflow_id
        @run_id = run_id
      end

      def self.from_hash(hash)
        new \
          workflow_id: hash["workflowId"],
          run_id:      hash["runId"]
      end

      def to_h
        { workflow_id: workflow_id, run_id: run_id }
      end
    end
  end
end
