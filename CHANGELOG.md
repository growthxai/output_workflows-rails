## [Unreleased]

## [0.4.0] - 2026-05-13

- Add `Client#trace_attributes(workflow_id, run_id: nil)` wrapping
  `GET /workflow/{id}/trace-attributes` and its pinned-run variant. Returns the
  parsed response body (cost / token usage / runtime / traceUrl).
- Map `424 FailedDependency` → new `WorkflowNotCompletedError` (matches the
  framework's semantics on `/result` and `/trace-log`).
- Map `5xx` → new `ServerError < APIError`.

## [0.1.0] - 2025-12-30

- Initial release
