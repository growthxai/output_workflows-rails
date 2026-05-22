## [Unreleased]

## [0.6.0] - 2026-05-22

- **BREAKING**: `Client#start_workflow` now returns an
  `OutputWorkflows::Responses::WorkflowDispatch` (carrying `workflow_id` and
  `run_id`) instead of a bare `workflow_id` string. Both fields are required
  to disambiguate runs under continue-as-new.
- **BREAKING**: `WorkflowExecution` requires `workflow_run_id`. Uniqueness
  moved from `workflow_id` alone to the composite `(workflow_id, workflow_run_id)`.
  `find_by_workflow_id!` removed; use `find_by_workflow_run!(workflow_id:, run_id:)`.
- `Client#workflow_status` and `Client#cancel_workflow` accept `run_id:` and
  route to the run-scoped endpoints (`/workflow/{id}/runs/{rid}/status`,
  `/workflow/{id}/runs/{rid}/stop`) when provided.
- `WorkflowExecution#poll_status!`, `#fetch_result!`, `#fetch_output!`,
  `#wait_for_completion!`, and `#cancel!` default `run_id:` to the
  execution's `workflow_run_id` so the calls stay pinned to the right run.
- `WebhookProcessor#execution` lookup uses the composite key.

## [0.5.0] - 2026-05-19

- Add cost rollup columns (`total_cost_micro_usd`, `total_tokens`,
  `total_http_calls`, `attributes_data`) to `output_workflow_executions`.
  Migration is owned by the consuming app — the gem ships only the model
  accessor.
- Add `WorkflowExecution::Cost` concern with `apply_workflow_result(result)`
  for idempotent rollup of the Output API's result envelope, and
  `cost_payload` returning a normalized contract for frontends.
- `WorkflowExecution#poll_status!`, `fetch_result!`, and
  `wait_for_completion!` now accept `run_id:` to target the run-scoped
  result endpoint (matters under retries / continue-as-new).
- Override `WorkflowExecution#serializable_hash` to include the `cost` block
  when populated.

## [0.4.0] - 2026-05-13

- Add `Executable#on_workflow_progress(execution)` lifecycle hook. Default is a no-op; webhook processors call it on every progress event so executable models can opt in to progress-driven state transitions (e.g. `:pending → :running`).

## [0.1.0] - 2025-12-30

- Initial release
