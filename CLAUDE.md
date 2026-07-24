# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`output_workflows-rails` — Ruby gem (Rails SDK) for starting and tracking Output.ai AI workflows. Supports synchronous (blocking wait), asynchronous (background polling), and webhook-driven execution. Alpha, GrowthX-internal. Ruby >= 3.2.

## Commands

```bash
bundle exec rake            # default: tests + rubocop
bundle exec rake test       # tests only
bundle exec rubocop         # lint only (double-quoted strings enforced)
# NOTE: rubocop currently reports pre-existing offenses on a clean tree, so
# `bundle exec rake` exits nonzero even with all tests green — gate on
# `bundle exec rake test` passing and on introducing no NEW rubocop offenses.

# Single file / single test
bundle exec ruby -Ilib:test test/test_client.rb
bundle exec ruby -Ilib:test test/test_client.rb -n /start_workflow/
```

## Architecture

Two layers, split by loading strategy:

**Core (framework-agnostic)** — loaded by `require "output_workflows"`:
- `Client` (`lib/output_workflows/client.rb`) — Faraday HTTP client; `start_workflow` (accepts `task_queue:` and `workflow_id:` options), `workflow_status`, `workflow_result(workflow_id, run_id)`, `wait_for_completion`, `cancel_workflow`.
- `Configuration` — ENV-driven (`OUTPUT_API_URL`, `OUTPUT_API_KEY`, `OUTPUT_WEBHOOK_SECRET`); defaults to `http://localhost:2000` in dev/test.
- `WebhookVerifier` — HMAC-SHA256 verification of the `X-Signature` header.
- `Responses::*` — typed wrappers (Status, WorkflowDispatch, WorkflowResult, WorkflowHistory).

**Rails layer** (`lib/output_workflows/rails/`) — required only when `::Rails` is defined; the railtie initializer loads the components (workflow_execution, executable, status_check_job, webhook_processor, progress_processor). Nothing here can be assumed loaded in plain-Ruby contexts.

Key Rails pieces:
- `WorkflowExecution` — ActiveRecord model tracking runs (`pending → running → completed|failed`). Split into concerns: `Events` (`append_event` writes per-webhook rows to the `output_workflow_execution_events` table, deduped by a unique DB index, not a validation), `Cost` (rollup logic), and the nested `Event` model.
- **Cost rollup design (load-bearing):** rollup columns are NOT incremented per event — a high-fan-out run would convoy on the row lock. Active executions derive totals live from the events table; terminal transitions recompute persisted columns once via one grouped SQL pass (`ROLLUP_AGGREGATES`, CASE not FILTER for sqlite portability). `rollups_computed_at` is a coverage watermark, not a timestamp of computation; recomputing is idempotent and self-heals late events (`rollups_stale` scope). Read `cost.rb`'s comments before touching any of this.
- **Executions store metadata only, never workflow output** — consumers call `fetch_output!` and extract to their own domain models. The table is purgeable (`purge_old`).
- `Executable` — concern for host-app models: `has_many :workflow_executions` (polymorphic), `workflow_status(name)`, `cancel_active_workflow!`, `on_workflow_progress` hook.
- `WebhookProcessor` (base) / `ProgressProcessor` — webhook handling; progress is a capped, lossy JSONB array for real-time display, not an audit log.

**Schema is owned by the consuming app**, not the gem: `rails generate output_workflows:install` copies a starter migration + initializer from `lib/generators/output_workflows/templates/`. Column changes therefore mean updating the template, the README schema table, AND documenting a follow-up migration for existing apps — the gem cannot migrate consumers.

## Tests

`test/test_helper.rb` boots ActiveRecord against in-memory sqlite, defines both tables inline, and manually requires the Rails components (no Rails app, no railtie). jsonb columns are stored as text and JSON-serialized to mimic Postgres behavior — keep new jsonb-backed columns consistent with that pattern, and mirror production schema changes in the helper's inline schema.

## Releasing

Bump `lib/output_workflows/version.rb` and add a CHANGELOG.md entry together; the version is breaking-change-versioned (see `0.8.0` rollup recompute entry).
