## [Unreleased]

## [0.6.0] - 2026-05-29

**Per-event cost hooks**

- **BREAKING**: `WorkflowExecution#apply_workflow_result` is removed.
  `mark_completed!` is state-only (status + completed_at). Cost data is now
  written from per-event webhooks instead of the Output API result envelope.
- Add `WorkflowExecution::Cost#apply_cost_event!(payload)` — idempotent,
  row-locked increment driven by `workflow_event.llm`,
  `workflow_event.http_cost`, and `workflow_event.http` actions. Rolls up both
  the totals (`total_cost_micro_usd`, `total_tokens`, `total_http_calls`) and
  per-attribute breakdowns (`total_llm_cost_micro_usd`,
  `total_http_cost_micro_usd`, `total_input_tokens`, `total_output_tokens`,
  `total_cached_input_tokens`, `total_reasoning_tokens`) from
  `payload.cost.total` and `payload.usage.*`.
- Add `WorkflowExecution::RollupEvent` AR class backing a new
  `output_workflow_execution_events` dedup table. Dedup is keyed by
  `(workflow_execution_id, event_id)` — repeat events return `false`.
- `cost_payload` now sources `token_usage` (including `reasoning_tokens`) and
  `cost_components` directly from the rollup columns. Legacy
  `cost_components_from_attributes` and `sum_usage_tokens` are removed.
- Install generator ships the new breakdown columns + the dedup-table
  migration. Existing installs add them manually (see README).

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
