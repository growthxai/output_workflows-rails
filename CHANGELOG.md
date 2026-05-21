## [Unreleased]

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
