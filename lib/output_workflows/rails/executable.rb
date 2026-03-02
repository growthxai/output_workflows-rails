# frozen_string_literal: true

module OutputWorkflows
  module Rails
    # Include in any model used as a workflow executable to get
    # convenience methods for status queries and cancellation.
    #
    #   class Persona < ApplicationRecord
    #     include OutputWorkflows::Rails::Executable
    #   end
    #
    #   persona.workflow_status("context_persona_enrichment")
    #   # => { active: true, started_at: <Time> }
    #   # => { active: false, last_error: "timeout" }
    #
    #   persona.cancel_active_workflow!("context_persona_enrichment")
    #
    module Executable
      extend ActiveSupport::Concern

      included do
        has_many :workflow_executions,
                 as: :executable,
                 class_name: "OutputWorkflows::Rails::WorkflowExecution",
                 dependent: :destroy
      end

      # Returns a status summary for the most recent execution of a workflow.
      def workflow_status(workflow_name)
        execs = workflow_executions.where(workflow_name: workflow_name)
        active = execs.active.first

        if active
          { active: true, started_at: active.started_at }
        else
          last = execs.terminal.order(updated_at: :desc).first
          { active: false, last_error: last&.status_failed? ? last&.error_message : nil }
        end
      end

      # Cancel all active executions of a workflow for this executable.
      # Cancels on the Output API and marks as failed locally.
      def cancel_active_workflow!(workflow_name)
        WorkflowExecution.cancel_active!(self, workflow_name)
      end
    end
  end
end
