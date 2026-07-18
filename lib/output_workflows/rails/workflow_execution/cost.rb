# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class WorkflowExecution < ActiveRecord::Base
      # Cost rollup behavior for WorkflowExecution.
      #
      # Cost data arrives as a stream of per-event webhooks (one per LLM call,
      # one per HTTP call) appended via `Events#append_event`. The rollup
      # columns are NOT incremented per event — a high-fan-out run (~100K HTTP
      # calls) would serialize every worker on this single row's lock and
      # convoy the whole database. Instead:
      #
      # - Active executions derive rollups live from the events table on read.
      # - Terminal transitions recompute the persisted columns once, as an
      #   absolute aggregate (`recompute_rollups`), stamping
      #   `rollups_computed_at`. Recomputing is idempotent and self-healing:
      #   late events are folded in by simply recomputing again.
      module Cost
        extend ActiveSupport::Concern

        # One grouped pass over the events table produces every rollup column.
        # CASE (not FILTER) keeps the SQL portable to the sqlite test harness.
        # Token columns sum unconditionally: non-llm rows store them as 0.
        ROLLUP_AGGREGATES = {
          total_cost_micro_usd: "COALESCE(SUM(cost_micro_usd), 0)",
          total_llm_cost_micro_usd: "COALESCE(SUM(CASE WHEN action_type = 'llm' THEN cost_micro_usd END), 0)",
          total_http_cost_micro_usd: "COALESCE(SUM(CASE WHEN action_type = 'http_cost' THEN cost_micro_usd END), 0)",
          total_http_calls: "COUNT(CASE WHEN action_type = 'http' THEN 1 END)",
          total_tokens: "COALESCE(SUM(total_tokens), 0)",
          total_input_tokens: "COALESCE(SUM(input_tokens), 0)",
          total_output_tokens: "COALESCE(SUM(output_tokens), 0)",
          total_cached_input_tokens: "COALESCE(SUM(cached_input_tokens), 0)",
          total_reasoning_tokens: "COALESCE(SUM(reasoning_tokens), 0)"
        }.freeze

        # The watermark is a COVERAGE GUARANTEE, not a wall-clock "computed at":
        # events with created_at at or before it are certainly folded into the
        # persisted rollups. It is stamped from before the aggregate runs (an
        # event committing mid-scan is invisible to the scan) and backdated by
        # this margin, because an event's created_at is assigned before its
        # INSERT commits - an append racing the recompute can land stamped
        # slightly in the past. The margin bounds that assignment-to-commit
        # latency; anything newer than the watermark counts as uncovered and is
        # picked up by `rollups_stale` sweeps until a recompute outruns it.
        COVERAGE_MARGIN = 60.seconds

        included do
          # Registered before the class body's `after_update
          # :trigger_completion_callback` (Cost is included first), so
          # completion callbacks observe recomputed totals. Hosts that
          # transition status via `update_all` bypass callbacks entirely and
          # must call `recompute_rollups` themselves after the transition.
          after_update :recompute_rollups, if: -> { saved_change_to_status? && terminal? }

          # Rows whose persisted rollups may be missing events: never recomputed
          # (NULL watermark), or an event landed past the coverage guarantee.
          # Plain column comparison - the margin lives in the watermark's write,
          # keeping this portable across adapters. Hosts sweep this (bounded by
          # their retention window) to fold in post-terminal stragglers.
          scope :rollups_stale, lambda {
            where(<<~SQL.squish)
              rollups_computed_at IS NULL OR EXISTS (
                SELECT 1 FROM #{Event.table_name} events
                WHERE events.execution_id = #{table_name}.id
                  AND events.created_at > #{table_name}.rollups_computed_at
              )
            SQL
          }
        end

        # Overwrite all rollup columns from the events table and stamp the
        # coverage watermark (see COVERAGE_MARGIN). `updated_at` is deliberately
        # left untouched. `update_columns` skips callbacks, so the terminal
        # `after_update` can't recurse.
        def recompute_rollups
          return unless rollups_recomputable?

          computed_at = Time.current - COVERAGE_MARGIN
          update_columns(derived_rollups.merge(rollups_computed_at: computed_at))
        end

        def cost_payload
          rollups = cost_rollups
          return nil unless has_cost_data?(rollups)

          {
            total_cost_usd: rollups[:total_cost_micro_usd] / 1_000_000.0,
            total_http_calls: rollups[:total_http_calls],
            token_usage: {
              input_tokens: rollups[:total_input_tokens],
              output_tokens: rollups[:total_output_tokens],
              cached_input_tokens: rollups[:total_cached_input_tokens],
              reasoning_tokens: rollups[:total_reasoning_tokens],
              total_tokens: rollups[:total_tokens]
            },
            trace_url: nil,
            cost_components: cost_components_from_rollups(rollups)
          }
        end

        private

        # Terminal rows read the persisted columns (the host may purge old
        # event rows after the run ends); active rows derive live so mid-run
        # cost is fresh without any write to this row.
        def cost_rollups
          terminal? ? slice(*ROLLUP_AGGREGATES.keys).symbolize_keys : derived_rollups
        end

        def derived_rollups
          values = events.pick(*ROLLUP_AGGREGATES.values.map { |sql| Arel.sql(sql) })
          ROLLUP_AGGREGATES.keys.zip(values.map(&:to_i)).to_h
        end

        # Guards every recompute path against the host's event retention: the
        # purge cuts by EVENT age, so recomputing from a purged events table
        # would overwrite valid totals with zeros. Executions younger than the
        # window provably still have every event. Older ones stay recomputable
        # while their oldest surviving event is inside the window - a run that
        # emitted across the purge boundary recomputes to the surviving subset,
        # which is exactly what derive-on-read was showing while it was active.
        # No surviving events on an old execution is indistinguishable from
        # fully purged: leave the persisted totals alone. `nil` retention means
        # events are kept forever.
        def rollups_recomputable?
          retention = OutputWorkflows.configuration.event_retention
          return true if retention.nil? || created_at > retention.ago

          oldest_event_at = events.minimum(:created_at)
          oldest_event_at.present? && oldest_event_at > retention.ago
        end

        def has_cost_data?(rollups)
          rollups[:total_cost_micro_usd].positive? ||
            rollups[:total_tokens].positive? ||
            rollups[:total_http_calls].positive?
        end

        def cost_components_from_rollups(rollups)
          components = []
          if rollups[:total_llm_cost_micro_usd].positive?
            components << { name: "llm:usage",
                            value_cents: (rollups[:total_llm_cost_micro_usd]  / 10_000.0).round }
          end
          if rollups[:total_http_cost_micro_usd].positive?
            components << { name: "http:request:cost",
                            value_cents: (rollups[:total_http_cost_micro_usd] / 10_000.0).round }
          end
          components
        end
      end
    end
  end
end
