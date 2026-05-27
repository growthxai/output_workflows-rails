# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution
      class RollupEvent < ::ActiveRecord::Base
        self.table_name = "output_workflow_execution_events"
        belongs_to :workflow_execution,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution",
                   inverse_of: :rollup_events
      end
    end
  end
end
