## [Unreleased]

## [0.5.0] - 2026-05-19

- Add cost rollup columns (`total_cost_micro_usd`, `total_tokens`,
  `total_http_calls`, `cost_data`) to `output_workflow_executions`.
- Add `output_workflow_execution_events` table and
  `WorkflowExecution::RollupEvent` model with a unique
  `(workflow_execution_id, event_id)` index for idempotent rollups.
- Add `WorkflowExecution::Cost` concern: `apply_cost_event!(payload)` for
  idempotent rollup of `workflow_event.llm`, `workflow_event.http_cost`, and
  `workflow_event.http` webhook actions, and `cost_payload` returning the
  contract atlas's frontend already consumes.
- Add `WorkflowEventProcessor` (subclass of `WebhookProcessor`) that looks up
  the execution by `workflowId` and dispatches to `apply_cost_event!`.
- Override `WorkflowExecution#serializable_hash` to include the `cost` block
  when populated.

## [0.4.0] - 2026-05-13

- Add `Executable#on_workflow_progress(execution)` lifecycle hook. Default is a no-op; webhook processors call it on every progress event so executable models can opt in to progress-driven state transitions (e.g. `:pending → :running`).

## [0.1.0] - 2025-12-30

- Initial release
