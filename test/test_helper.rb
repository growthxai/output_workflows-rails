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
    t.string :workflow_id, null: false
    t.string :workflow_run_id, null: false
    t.string :workflow_name, null: false, index: true
    t.index [:workflow_id, :workflow_run_id], unique: true
    t.string :status, null: false, default: "pending", index: true
    t.text :input_params
    t.text :progress
    t.text :error_message
    t.datetime :started_at
    t.datetime :completed_at
    t.bigint  :total_cost_micro_usd,       null: false, default: 0
    t.bigint  :total_http_cost_micro_usd,  null: false, default: 0
    t.integer :total_http_calls,           null: false, default: 0
    t.bigint  :total_llm_cost_micro_usd,   null: false, default: 0
    t.bigint  :total_tokens,               null: false, default: 0
    t.integer :total_input_tokens,         null: false, default: 0
    t.integer :total_output_tokens,        null: false, default: 0
    t.integer :total_cached_input_tokens,  null: false, default: 0
    t.integer :total_reasoning_tokens,     null: false, default: 0
    t.text    :events
    t.timestamps
  end

  create_table :output_workflow_execution_events do |t|
    t.references :execution, null: false
    t.string  :event_id, null: false
    t.string  :action_type, null: false
    t.string  :workflow_name, null: false
    t.string  :provider
    t.string  :model_id
    t.string  :url
    t.bigint  :cost_micro_usd,      null: false, default: 0
    t.integer :input_tokens,        null: false, default: 0
    t.integer :output_tokens,       null: false, default: 0
    t.integer :cached_input_tokens, null: false, default: 0
    t.integer :reasoning_tokens,    null: false, default: 0
    t.bigint  :total_tokens,        null: false, default: 0
    t.integer :duration_ms
    t.datetime :occurred_at, null: false
    t.timestamps
    t.index %i[execution_id event_id], unique: true
  end
end

require "output_workflows/rails/workflow_execution"
require "output_workflows/rails/webhook_processor"

# Sqlite doesn't speak jsonb, so the schema above stores jsonb-backed columns
# as text. Serialize them as JSON so tests exercise the same hash-in/hash-out
# shape that Postgres's jsonb adapter provides in production.
OutputWorkflows::Rails::WorkflowExecution.serialize :events, coder: JSON, type: Array, default: []
OutputWorkflows::Rails::WorkflowExecution.serialize :progress, coder: JSON
OutputWorkflows::Rails::WorkflowExecution.serialize :input_params, coder: JSON
