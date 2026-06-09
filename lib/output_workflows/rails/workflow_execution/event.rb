# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ActiveRecord::Base
      class Event < ActiveRecord::Base
        self.table_name = "output_workflow_execution_events"

        belongs_to :execution,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution",
                   inverse_of: :events

        enum :action_type, %w[llm http http_cost].index_by(&:itself), validate: true

        validates :event_id, presence: true
        # validates :event_id, uniqueness: { scope: :execution_id } Intentionally omitted for performance. Handled by the database index.

        ActiveSupport.run_load_hooks(:output_workflow_execution_event, self)
      end
    end
  end
end
