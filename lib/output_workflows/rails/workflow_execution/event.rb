# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ::ActiveRecord::Base
      # One row per webhook event (LLM call, HTTP call, etc.) emitted by a
      # workflow run. Append-only: rows are inserted by `Events#append_event`
      # and never mutated. Replaces the legacy `events` JSONB array on
      # `output_workflow_executions` — appending via plain INSERT avoids the
      # per-row `FOR UPDATE` lock convoy and O(n^2) array rewrites that array
      # design suffered under high fan-out.
      #
      # Dedup is enforced by a `UNIQUE (execution_id, event_id)` index at the
      # database level (no model-level uniqueness validation — that would add a
      # SELECT to every insert on the hot webhook path).
      class Event < ::ActiveRecord::Base
        self.table_name = "output_workflow_execution_events"

        belongs_to :execution,
                   class_name: "OutputWorkflows::Rails::WorkflowExecution",
                   foreign_key: :execution_id,
                   inverse_of: :execution_events

        # Auto-generates `.llm` / `.http` / `.http_cost` scopes and predicates,
        # consistent with `enum :status` on WorkflowExecution.
        enum :action_type, %w[llm http http_cost].index_by(&:itself), validate: true

        validates :event_id, presence: true

        # Lets a host app inject behavior (e.g. denormalizing workspace_id from
        # the parent) without the gem knowing about it — mirrors the
        # `:output_workflow_execution` hook on WorkflowExecution.
        ActiveSupport.run_load_hooks(:output_workflow_execution_event, self)
      end
    end
  end
end
