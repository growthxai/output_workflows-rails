## [Unreleased]

## [0.6.0] - 2026-06-01

**Per-event cost hooks + JSONB log**

- **BREAKING**: Replace `WorkflowExecution#apply_workflow_result` with
  per-event `apply_cost_event!(payload)`. Idempotent, row-locked,
  dispatches on `workflow_event.llm` / `workflow_event.http_cost` /
  `workflow_event.http`.
- **BREAKING**: `mark_completed!` is state-only — no `result:` kwarg. Guards
  against clobbering a prior `failed` state.
- Per-event detail lives on `output_workflow_executions.cost_events` (a
  JSONB array). Dedup is in-memory membership check inside `with_lock`.
- Adds 6 breakdown rollup columns: `total_llm_cost_micro_usd`,
  `total_http_cost_micro_usd`, `total_input_tokens`, `total_output_tokens`,
  `total_cached_input_tokens`, `total_reasoning_tokens`.
- Drops the unused `cost_data` and `attributes_data` columns from the
  install migration.
- `cost_payload` sources `token_usage` and `cost_components` from rollup
  columns. Legacy `cost_components_from_attributes` / `sum_usage_tokens` /
  the dedup-table model are removed.

## [0.5.0] - 2026-05-22

**Cost rollup**

- Add cost rollup columns (`total_cost_micro_usd`, `total_tokens`,
  `total_http_calls`, `attributes_data`) to `output_workflow_executions`.
  Migration is owned by the consuming app — the gem ships only the model
  accessor.
- Add `WorkflowExecution::Cost` concern with `apply_workflow_result(result)`
  for idempotent rollup of the Output API's result envelope, and
  `cost_payload` returning a normalized contract for frontends.
- Override `WorkflowExecution#serializable_hash` to include the `cost` block
  when populated.

**Run-scoped client + execution lookups (continue-as-new safety)**

- **BREAKING**: `Client#start_workflow` returns an
  `OutputWorkflows::Responses::WorkflowDispatch` carrying both `workflow_id`
  and `run_id` instead of a bare `workflow_id` string. Both fields are
  required to disambiguate runs under continue-as-new.
- **BREAKING**: `WorkflowExecution` requires `workflow_run_id`. Uniqueness
  moved from `workflow_id` alone to the composite
  `(workflow_id, workflow_run_id)`. `find_by_workflow_id!` removed; use
  `find_by_workflow_run!(workflow_id:, run_id:)`.
- `Client#workflow_status`, `#cancel_workflow`, `#workflow_result`,
  `#workflow_history`, and `#wait_for_completion` accept `run_id:` and route
  to the run-scoped endpoints (`/workflow/{id}/runs/{rid}/...`) when
  provided.
- `WorkflowExecution#poll_status!`, `#fetch_result!`, `#fetch_output!`,
  `#wait_for_completion!`, and `#cancel!` default `run_id:` to the
  execution's `workflow_run_id` so calls stay pinned to the right run.
- `WebhookProcessor#execution` prefers the composite `(workflow_id, run_id)`
  lookup, falling back to a workflow_id-only lookup when the incoming
  payload lacks `runId`. Emits a warning on the fallback path so legacy
  producers can be tracked down ahead of the callWebhook → lifecycle hook
  migration.

## [0.4.0] - 2026-05-13

- Add `Executable#on_workflow_progress(execution)` lifecycle hook. Default is a no-op; webhook processors call it on every progress event so executable models can opt in to progress-driven state transitions (e.g. `:pending → :running`).

## [0.1.0] - 2025-12-30

- Initial release
