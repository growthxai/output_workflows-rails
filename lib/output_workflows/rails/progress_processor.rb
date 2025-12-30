# frozen_string_literal: true

module OutputWorkflows
  module Rails
    # Processes workflow_progress webhooks by updating the
    # WorkflowExecution progress array.
    #
    # Expected payload format:
    #   {
    #     "action": "workflow_progress",
    #     "workflowId": "wf-123",
    #     "name": "Processing step 1",
    #     "extraInfo": "Optional details"
    #   }
    #
    class ProgressProcessor < WebhookProcessor
      def process
        return unless execution&.active?

        execution.append_progress!(
          name: payload["name"],
          extra_info: payload["extraInfo"]
        )
      end
    end
  end
end
