## [Unreleased]

## [0.7.0] - 2026-05-29

**Per-attribute cost rollup columns**

- Extend `apply_cost_event!` to also roll up per-attribute breakdowns into
  dedicated columns as events arrive:
  - `workflow_event.llm` now also increments
    `total_llm_cost_micro_usd`, `total_input_tokens`,
    `total_output_tokens`, `total_cached_input_tokens`, and
    `total_reasoning_tokens` from the event's `cost.total` and
    `usage.{inputTokens,outputTokens,cachedInputTokens,reasoningTokens}`.
  - `workflow_event.http_cost` now also increments
    `total_http_cost_micro_usd` from the event's `cost.total`.
- `cost_payload` now sources
  `token_usage.{input_tokens,output_tokens,cached_input_tokens,reasoning_tokens}`
  and `cost_components` directly from these columns instead of parsing
  `attributes_data`. `cost_components` emits `llm:usage` and/or
  `http:request:cost` entries based on the corresponding rollup column being
  positive. The legacy `cost_components_from_attributes` and
  `sum_usage_tokens` helpers are removed.
- The install generator's `create_output_workflow_executions` migration
  template now ships the new breakdown columns
  (`total_input_tokens`, `total_output_tokens`, `total_cached_input_tokens`,
  `total_reasoning_tokens`, `total_llm_cost_micro_usd`,
  `total_http_cost_micro_usd`) so fresh installs pick them up automatically.
  Existing installs need to add the columns manually — see README.

## [0.6.0] - 2026-05-27

**Per-event cost hooks**

- **BREAKING**: Cost data is no longer written from the Output API result
  envelope at workflow completion. `WorkflowExecution#apply_workflow_result`
  is removed, and `mark_completed!` no longer touches the cost columns.
  Lifecycle is now state-only (status + completion timestamp).
- Add `WorkflowExecution::Cost#apply_cost_event!(payload)` — an idempotent,
  row-locked increment of `total_cost_micro_usd` / `total_tokens` /
  `total_http_calls` driven by per-event webhooks. Supports
  `workflow_event.llm`, `workflow_event.http_cost`, and `workflow_event.http`
  actions; other actions no-op after dedup.
- Add `WorkflowExecution::RollupEvent` AR class backing a new
  `output_workflow_execution_events` dedup table. Dedup is keyed by
  `(workflow_execution_id, event_id)` and enforced by a unique index — repeat
  events return `false` and do not double-increment.
- Install generator now emits a second migration creating
  `output_workflow_execution_events`. Existing installs need to add the
  table manually (see README).
- `cost_payload` is unchanged and stays compatible with the same columns.

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
