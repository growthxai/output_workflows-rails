## [0.8.0] - 2026-07-17

**Terminal cost rollups (kills the per-event hot-row UPDATE)**

- **BREAKING**: `append_event` no longer increments the `total_*` rollup
  columns per event. A high-fan-out run (~100K HTTP calls) serialized every
  worker on the execution row's lock and convoyed the whole database
  (growthxai/atlas 2026-07-09 / 07-14 incidents). Event appends are now pure
  INSERTs — no write to `output_workflow_executions` at all.
- Rollups are recomputed as one absolute grouped aggregate over the events
  table at terminal transitions (`after_update` on status → completed/failed),
  stamping a new `rollups_computed_at` watermark column. **Hosts must add the
  column** (`rollups_computed_at :datetime`, nullable). Recomputing is
  idempotent and self-healing — call `recompute_rollups` again to fold in late
  events. The watermark is a coverage guarantee (stamped pre-aggregate, minus
  `Cost::COVERAGE_MARGIN`): events at or before it are certainly counted. The
  new `rollups_stale` scope selects rows whose rollups may be missing events
  (NULL watermark, or an event past the coverage guarantee) — sweep it,
  bounded by your retention window, to reconcile post-terminal stragglers.
- **BREAKING**: hosts that transition status via `update_all` (no AR
  callbacks) must call `recompute_rollups` explicitly after a terminal
  transition.
- `cost_payload` derives rollups live from the events table for active
  executions (fresh mid-run cost without any hot-row write) and reads the
  persisted columns for terminal ones.
- New config `event_retention` (duration, default nil = events kept forever):
  hosts that purge old event rows must set it — `recompute_rollups` no-ops on
  executions older than the retention so a recompute can never zero out valid
  totals from a purged events table.

**Caller-supplied workflow id**

- `Client#start_workflow` now forwards a `workflow_id:` option to `POST
  /workflow/start` as `workflowId`. Lets a caller pass a readable, domain-scoped
  id (e.g. `"acme-x1y2z3"`) instead of the opaque server-generated nanoid. Must
  be unique; omitting it preserves the prior server-minted behavior.

## [0.6.1] - 2026-06-05

**Tolerate un-stoppable runs on cancel**

- `Client#cancel_workflow` wraps an unexpected stop `4xx` (e.g. a `400` for a
  legacy / non-existent run) as `OutputWorkflows::APIError` instead of
  re-raising the raw Faraday error. `WorkflowExecution#cancel!` already rescues
  `APIError`, so it now marks the stale execution failed locally and lets a new
  dispatch proceed instead of crashing the dispatching job (COS-1141).

## [0.6.0] - 2026-06-01

**Per-event cost hooks + JSONB log**

- **BREAKING**: Replace `WorkflowExecution#apply_workflow_result` with
  per-event `append_event(payload)`. Idempotent, row-locked,
  dispatches on `workflow_event.llm` / `workflow_event.http_cost` /
  `workflow_event.http`.
- **BREAKING**: `mark_completed!` is state-only — no `result:` kwarg. Guards
  against clobbering a prior `failed` state.
- Per-event detail lives on `output_workflow_executions.events` (a
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
