# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class Status
      # Workflow status constants
      STATUS_PENDING = "PENDING"
      STATUS_RUNNING = "RUNNING"
      STATUS_COMPLETED = "COMPLETED"
      STATUS_FAILED = "FAILED"
      STATUS_TERMINATED = "TERMINATED"
      STATUS_TIMED_OUT = "TIMED_OUT"
      STATUS_CANCELED = "CANCELED"

      attr_reader :workflow_id, :run_id, :status_name, :status_code, :history_url

      def initialize(workflow_id:, run_id: nil, status_name:, status_code: nil, history_url: nil)
        @workflow_id = workflow_id
        @run_id = run_id
        @status_name = status_name
        @status_code = status_code
        @history_url = history_url
      end

      def self.from_hash(hash)
        new(
          workflow_id: hash["workflowId"],
          run_id: hash["runId"],
          status_name: hash.dig("status", "name") || hash["statusName"],
          status_code: hash.dig("status", "code") || hash["statusCode"],
          history_url: hash["historyUrl"]
        )
      end

      def pending?
        status_name == STATUS_PENDING
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
          run_id: run_id,
          status_name: status_name,
          status_code: status_code,
          history_url: history_url
        }
      end
    end
  end
end
