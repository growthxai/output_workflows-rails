# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class StatusCheckJob < ::ActiveJob::Base
      MAX_RETRIES = 3
      RETRY_DELAY = 10

      retry_on OutputWorkflows::APIError, wait: RETRY_DELAY, attempts: MAX_RETRIES
      retry_on Faraday::Error, wait: RETRY_DELAY, attempts: MAX_RETRIES

      queue_as { OutputWorkflows.configuration.job_queue }

      def perform(workflow_execution_id, retry_count: 0)
        execution = OutputWorkflows::Rails::WorkflowExecution.find(workflow_execution_id)

        # Skip if already in terminal state
        return if execution.terminal?

        # Poll status and update execution
        completed = execution.poll_status!

        # If not completed, schedule another check
        unless completed
          self
            .class
            .set(wait: OutputWorkflows.configuration.default_poll_interval.seconds)
            .perform_later(workflow_execution_id)
        end
      rescue ActiveRecord::RecordNotFound
        # Don't retry if record doesn't exist
        nil
      rescue StandardError => e
        # Retry with exponential backoff
        if retry_count < MAX_RETRIES
          self
            .class
            .set(wait: (RETRY_DELAY * (retry_count + 1)).seconds)
            .perform_later(workflow_execution_id, retry_count: retry_count + 1)
        else
          # Max retries exceeded, mark as failed
          execution&.mark_failed!("Max retries exceeded: #{e.message}")
        end
      end
    end
  end
end
