# frozen_string_literal: true

module OutputWorkflows
  module Rails
    # Base class for processing Output.ai webhooks.
    #
    # Subclass this to handle specific webhook actions:
    #
    #   class MyProcessor < OutputWorkflows::Rails::WebhookProcessor
    #     def process
    #       # Your logic here
    #     end
    #   end
    #
    class WebhookProcessor
      attr_reader :payload

      def initialize(payload)
        @payload = normalize_payload(payload)
      end

      # Override in subclasses to process the webhook
      def process
        raise NotImplementedError, "Subclasses must implement #process"
      end

      # Extract workflow ID from payload
      def workflow_id
        payload["workflowId"]
      end

      # Extract run ID from payload. Required to identify the specific run
      # under continue-as-new where multiple runs share a workflow_id.
      def run_id
        payload["runId"]
      end

      # Extract action from payload
      def action
        payload["action"]
      end

      # Find the associated WorkflowExecution record. Falls back to the latest
      # run by `created_at` when payload lacks `runId` — legacy producers; remove
      # once they migrate to lifecycle webhooks.
      def execution
        @execution ||=
          if run_id
            WorkflowExecution.find_by(workflow_id: workflow_id, workflow_run_id: run_id)
          elsif workflow_id
            warn_legacy_payload
            WorkflowExecution.where(workflow_id: workflow_id).order(created_at: :desc).first
          end
      end

      private

      def warn_legacy_payload
        return unless defined?(::Rails)
        ::Rails.logger.warn(
          "[OutputWorkflows::WebhookProcessor] Payload missing runId for " \
          "workflow_id=#{workflow_id}; falling back to latest run"
        )
      end

      def normalize_payload(data)
        case data
        when String
          JSON.parse(data)
        when Hash
          stringify_keys(data)
        else
          stringify_keys(data.to_h)
        end
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end
    end
  end
end
