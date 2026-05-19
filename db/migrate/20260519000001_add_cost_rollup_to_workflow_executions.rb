# frozen_string_literal: true

class AddCostRollupToWorkflowExecutions < ActiveRecord::Migration[7.1]
  def change
    change_table :output_workflow_executions do |t|
      t.bigint  :total_cost_micro_usd, default: 0, null: false
      t.bigint  :total_tokens,         default: 0, null: false
      t.integer :total_http_calls,     default: 0, null: false
      t.jsonb   :cost_data,            default: {}, null: false
    end
  end
end
