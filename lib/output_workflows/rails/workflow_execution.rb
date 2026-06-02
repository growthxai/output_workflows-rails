# frozen_string_literal: true

require_relative "workflow_execution/events"
require_relative "workflow_execution/cost"

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      self.table_name = OutputWorkflows.configuration.table_name

      include OutputWorkflows::Rails::WorkflowExecution::Events
      include OutputWorkflows::Rails::WorkflowExecution::Cost

      belongs_to :executable, polymorphic: true, optional: true

      enum :status, %w[pending running completed failed].index_by(&:itself), prefix: true

      validates :workflow_id, :workflow_run_id, presence: true
      validates :workflow_id, uniqueness: { scope: :workflow_run_id }
      validates :workflow_name, presence: true
      validates :status, presence: true

      scope :active, -> { where(status: %i[pending running]) }
      scope :terminal, -> { where(status: %i[completed failed]) }
      scope :for_workflow, ->(name) { where(workflow_name: name) }
      scope :for_executable, ->(executable) { where(executable: executable) }

      before_create :set_started_at, if: -> { status_running? || status_completed? }
      before_save :set_completed_at, if: -> { status_changed? && (status_completed? || status_failed?) }
      after_update :trigger_completion_callback, if: -> { saved_change_to_status? && terminal? }

      class << self
        # Look up a specific run by composite key. Both args required —
        # multiple runs can share a workflow_id under continue-as-new.
        def find_by_workflow_run!(workflow_id:, run_id:)
          find_by!(workflow_id: workflow_id, workflow_run_id: run_id)
        end

        def purge_old(days: 30)
          terminal.where(created_at: ..days.days.ago).delete_all
        end

        # Cancel all active executions of a workflow for a given executable.
        # Cancels on the Output API and marks as failed locally.
        #
        #   WorkflowExecution.cancel_active!(persona, "context_persona_enrichment")
        def cancel_active!(executable, workflow_name)
          for_executable(executable)
            .for_workflow(workflow_name)
            .active
            .find_each(&:cancel!)
        end
      end

      # Poll status from Output API and update the row.
      def poll_status!(run_id: workflow_run_id)
        client = output_client
        status_response = client.workflow_status(workflow_id, run_id: run_id)

        return false unless status_response

        if status_response.completed?
          mark_completed!
          true
        elsif status_response.failed?
          mark_failed!(status_response.status_name)
          true
        elsif status_response.running?
          mark_running! if status_pending?
          false
        else
          false
        end
      end

      # Fetch the full workflow result envelope from Output API and return it.
      # Note: This method does NOT persist the output to the database.
      # Users should extract relevant data to their domain models instead.
      def fetch_result!(run_id: workflow_run_id)
        client = output_client
        client.workflow_result(workflow_id, run_id: run_id)
      end

      # Backwards-compatible accessor returning just the output payload.
      def fetch_output!(run_id: workflow_run_id)
        fetch_result!(run_id: run_id)&.output
      end

      # Wait for workflow completion synchronously and return the result envelope.
      def wait_for_completion!(poll_interval: 5, timeout: 300, run_id: workflow_run_id)
        client = output_client
        output_response =
          client.wait_for_completion(
            workflow_id,
            poll_interval: poll_interval,
            timeout: timeout,
            run_id: run_id
          )

        mark_completed!

        output_response
      rescue OutputWorkflows::WorkflowFailedError => e
        mark_failed!(e.status_name)
        raise
      rescue OutputWorkflows::TimeoutError
        mark_failed!("timed_out")
        raise
      end

      # Cancel the workflow on Output API and mark as failed locally.
      def cancel!
        return if terminal? # Already completed/failed

        client = output_client
        cancelled = client.cancel_workflow(workflow_id, run_id: workflow_run_id)

        if cancelled
          mark_failed!("Cancelled by user")
          log_info("Workflow #{workflow_id} cancelled successfully")
        else
          # Workflow doesn't exist on API - mark as failed anyway
          mark_failed!("Cancelled (workflow not found on API)")
          log_warn("Workflow #{workflow_id} not found on API, marked as cancelled locally")
        end

        true
      rescue OutputWorkflows::APIError => e
        log_error("Failed to cancel workflow #{workflow_id}: #{e.message}")
        # Mark as failed locally even if API call fails
        mark_failed!("Cancellation failed: #{e.message}")
        false
      end

      # Append a progress entry (used by webhook processor)
      def append_progress!(name:, extra_info: nil)
        entry = {
          name: name,
          extra_info: extra_info,
          at: Time.current.iso8601
        }

        max_entries = OutputWorkflows.configuration.max_progress_entries
        new_progress = (progress || []).prepend(entry).first(max_entries)
        update!(progress: new_progress, status: :running)
      end

      # Clear progress on completion (keeps table lean)
      def clear_progress!
        update!(progress: []) if terminal?
      end

      # State transitions
      def mark_running!
        update!(status: :running, started_at: Time.current)
      end

      # Mark this execution completed. State-only transition — cost data
      # arrives via per-event webhooks (`append_event`), not from the
      # workflow result envelope.
      def mark_completed!
        return if terminal?
        update!(status: :completed, completed_at: Time.current)
      end

      def mark_failed!(error_message = nil)
        update!(status: :failed, completed_at: Time.current, error_message: error_message)
      end

      # Status helpers
      def terminal?
        status_completed? || status_failed?
      end

      def active?
        status_pending? || status_running?
      end

      def serializable_hash(options = nil)
        hash = super
        hash["cost"] = cost_payload if cost_payload
        hash
      end

      private

      def output_client
        @output_client ||= OutputWorkflows::Client.new
      end

      def set_started_at
        self.started_at ||= Time.current
      end

      def set_completed_at
        self.completed_at = Time.current if terminal?
      end

      # Trigger completion callback on executable model if it responds to the method
      # This allows executable models to define their own completion handling logic
      # without coupling the library to specific domain models
      def trigger_completion_callback
        return unless executable
        return unless executable.respond_to?(:handle_workflow_completion)

        executable.handle_workflow_completion(self)
      end

      def log_info(message)
        ::Rails.logger.info(message) if defined?(::Rails)
      end

      def log_warn(message)
        ::Rails.logger.warn(message) if defined?(::Rails)
      end

      def log_error(message)
        ::Rails.logger.error(message) if defined?(::Rails)
      end

      ActiveSupport.run_load_hooks(:output_workflow_execution, self)
    end
  end
end
