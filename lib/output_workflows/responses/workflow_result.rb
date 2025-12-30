# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class WorkflowResult
      attr_reader :workflow_id, :run_id, :input, :output

      def initialize(workflow_id:, run_id:, input: nil, output: nil)
        @workflow_id = workflow_id
        @run_id = run_id
        @input = input
        @output = output
      end

      def self.from_hash(hash)
        workflow_data = hash["workflow"] || hash
        new(
          workflow_id: workflow_data["workflowId"],
          run_id: workflow_data["runId"],
          input: workflow_data["input"],
          output: workflow_data["output"]
        )
      end

      def to_h
        { workflow_id: workflow_id, run_id: run_id, input: input, output: output }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
