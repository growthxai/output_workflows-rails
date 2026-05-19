# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      class RollupEvent < ::ActiveRecord::Base
        self.table_name = "output_workflow_execution_events"

        belongs_to :workflow_execution,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution"

        validates :event_id, presence: true
      end
    end
  end
end
