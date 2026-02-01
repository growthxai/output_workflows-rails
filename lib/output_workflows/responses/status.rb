# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class Status
      # Workflow status constants
      STATUS_RUNNING = "running"
      STATUS_COMPLETED = "completed"
      STATUS_FAILED = "failed"
      STATUS_CANCELED = "canceled"
      STATUS_TERMINATED = "terminated"
      STATUS_TIMED_OUT = "timed_out"
      STATUS_CONTINUED = "continued"

      attr_reader :workflow_id, :status_name, :started_at, :completed_at

      def initialize(workflow_id:, status_name:, started_at: nil, completed_at: nil)
        @workflow_id = workflow_id
        @status_name = status_name
        @started_at = started_at
        @completed_at = completed_at
      end

      def self.from_hash(hash)
        new(
          workflow_id: hash["workflowId"],
          status_name: hash["status"],
          started_at: hash["startedAt"],
          completed_at: hash["completedAt"]
        )
      end

      def running?
        status_name == STATUS_RUNNING
      end

      def completed?
        status_name == STATUS_COMPLETED
      end

      def failed?
        [STATUS_FAILED, STATUS_TERMINATED, STATUS_TIMED_OUT, STATUS_CANCELED].include?(status_name)
      end

      def terminal?
        completed? || failed?
      end

      def to_h
        {
          workflow_id: workflow_id,
          status_name: status_name,
          started_at: started_at,
          completed_at: completed_at
        }
      end
    end
  end
end
