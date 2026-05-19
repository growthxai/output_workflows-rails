# frozen_string_literal: true

class CreateOutputWorkflowExecutionEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :output_workflow_execution_events do |t|
      t.belongs_to :workflow_execution,
                   null: false,
                   foreign_key: { to_table: :output_workflow_executions, on_delete: :cascade }
      t.string :event_id, null: false
      t.timestamps
    end

    add_index :output_workflow_execution_events,
              %i[workflow_execution_id event_id],
              unique: true
  end
end
