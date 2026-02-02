# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class WorkflowResult
      attr_reader :workflow_id, :output, :trace

      def initialize(workflow_id:, output: nil, trace: nil)
        @workflow_id = workflow_id
        @output = output
        @trace = trace
      end

      def self.from_hash(hash)
        new(
          workflow_id: hash["workflowId"],
          output: hash["output"],
          trace: hash["trace"]
        )
      end

      def to_h
        { workflow_id: workflow_id, output: output, trace: trace }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
