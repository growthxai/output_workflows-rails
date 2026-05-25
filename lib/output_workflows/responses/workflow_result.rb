# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class WorkflowResult
      attr_reader :workflow_id, :output, :trace, :aggregations, :attributes

      def initialize(workflow_id:, output: nil, trace: nil, aggregations: nil, attributes: nil)
        @workflow_id = workflow_id
        @output = output
        @trace = trace
        @aggregations = aggregations
        @attributes = attributes
      end

      def self.from_hash(hash)
        new(
          workflow_id:  hash["workflowId"],
          output:       hash["output"],
          trace:        hash["trace"],
          aggregations: hash["aggregations"],
          attributes:   hash["attributes"]
        )
      end

      def to_h
        {
          workflow_id:  workflow_id,
          output:       output,
          trace:        trace,
          aggregations: aggregations,
          attributes:   attributes
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
