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

      # Extract action from payload
      def action
        payload["action"]
      end

      # Find the associated WorkflowExecution record
      def execution
        @execution ||= WorkflowExecution.find_by(workflow_id: workflow_id)
      end

      private

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
