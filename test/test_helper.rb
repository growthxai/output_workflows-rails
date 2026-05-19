# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "output_workflows"

require "minitest/autorun"
require "webmock/minitest"

# Default to a known test URL so Configuration#validate! passes everywhere.
OutputWorkflows.configure do |config|
  config.api_url = "http://test.local"
end

# ----------------------------------------------------------------------------
# ActiveRecord test harness
# ----------------------------------------------------------------------------
# The Rails components ship as a railtie-loaded extension and are not required
# unless a host Rails app is present. For tests we boot ActiveRecord against an
# in-memory sqlite database, create the gem's tables, and load the Rails
# modules manually in the same order the railtie would.
require "active_record"
require "active_support"
require "active_support/core_ext"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  self.verbose = false

  create_table :output_workflow_executions do |t|
    t.references :executable, polymorphic: true
    t.string :workflow_id, null: false, index: { unique: true }
    t.string :workflow_run_id
    t.string :workflow_name, null: false, index: true
    t.string :status, null: false, default: "pending", index: true
    t.text :input_params
    t.text :progress
    t.text :error_message
    t.datetime :started_at
    t.datetime :completed_at
    t.bigint :total_cost_micro_usd, null: false, default: 0
    t.bigint :total_tokens,         null: false, default: 0
    t.integer :total_http_calls,    null: false, default: 0
    t.text :cost_data
    t.timestamps
  end

  create_table :output_workflow_execution_events do |t|
    t.references :workflow_execution, null: false, foreign_key: { to_table: :output_workflow_executions }
    t.string :event_id, null: false
    t.timestamps
  end
  add_index :output_workflow_execution_events,
            %i[workflow_execution_id event_id],
            unique: true
end

require "output_workflows/rails/workflow_execution/rollup_event"
require "output_workflows/rails/workflow_execution/cost"
require "output_workflows/rails/workflow_execution"
require "output_workflows/rails/webhook_processor"
require "output_workflows/rails/workflow_event_processor"

# Sqlite doesn't speak jsonb, so the schema above stores cost_data as text.
# Serialize it as JSON so tests exercise the same hash-in/hash-out shape that
# Postgres's jsonb adapter provides in production.
OutputWorkflows::Rails::WorkflowExecution.serialize :cost_data, coder: JSON
OutputWorkflows::Rails::WorkflowExecution.serialize :progress, coder: JSON
OutputWorkflows::Rails::WorkflowExecution.serialize :input_params, coder: JSON
