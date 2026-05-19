# frozen_string_literal: true

module OutputWorkflows
  module Rails
    # Processes `workflow_event.*` webhooks from Output.ai's usage_events hook.
    #
    # Three actions are handled, each carrying an `event_id` used for idempotent
    # rollup onto the WorkflowExecution row:
    #
    #   workflow_event.llm        cost.total, usage.totalTokens, modelId, …
    #   workflow_event.http_cost  cost.total, url, …
    #   workflow_event.http       method, url, status, durationMs, outcome, …
    #
    # Usage:
    #
    #   OutputWorkflows::Rails::WorkflowEventProcessor.new(payload).process
    #
    # Returns the WorkflowExecution that received the rollup, or nil when the
    # workflowId in the payload doesn't match any known execution (the caller
    # can use the return value to decide whether to forward the event to a
    # detail-layer store like ClickHouse).
    class WorkflowEventProcessor < WebhookProcessor
      def process
        return nil if execution.nil?

        execution.apply_cost_event!(payload)
        execution
      end
    end
  end
end
