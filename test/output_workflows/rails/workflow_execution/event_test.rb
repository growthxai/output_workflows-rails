# frozen_string_literal: true

require "test_helper"
require "active_support/test_case"

module OutputWorkflows
  module Rails
    class WorkflowExecution
      class EventTest < ActiveSupport::TestCase
        Event = OutputWorkflows::Rails::WorkflowExecution::Event

        setup do
          Event.delete_all
          WorkflowExecution.delete_all
          @execution = WorkflowExecution.create!(
            workflow_id: "wf_evt",
            workflow_run_id: "run_evt",
            workflow_name: "context_persona_enrichment",
            status: "pending"
          )
        end

        test "persists an event row linked to its execution" do
          event = @execution.events.create!(
            event_id: "evt_1",
            action_type: "llm",
            workflow_name: "context_persona_enrichment",
            occurred_at: Time.current.utc
          )

          assert event.persisted?
          assert_equal @execution, event.execution
          assert_equal [event], @execution.events.to_a
        end

        test "enforces (execution_id, event_id) uniqueness at the database level" do
          @execution.events.create!(
            event_id: "evt_dup", action_type: "llm",
            workflow_name: "wf", occurred_at: Time.current.utc
          )

          assert_raises ActiveRecord::RecordNotUnique do
            @execution.events.create!(
              event_id: "evt_dup", action_type: "http",
              workflow_name: "wf", occurred_at: Time.current.utc
            )
          end
        end

        test "the same event_id is allowed under a different execution" do
          other = WorkflowExecution.create!(
            workflow_id: "wf_other", workflow_run_id: "run_other",
            workflow_name: "wf", status: "pending"
          )
          @execution.events.create!(
            event_id: "evt_shared", action_type: "llm",
            workflow_name: "wf", occurred_at: Time.current.utc
          )

          assert_nothing_raised do
            other.events.create!(
              event_id: "evt_shared", action_type: "llm",
              workflow_name: "wf", occurred_at: Time.current.utc
            )
          end
        end

        test "append_event stores the pricing columns and activity id the payload carries" do
          @execution.append_event(
            "eventId" => "evt_priced",
            "action" => "workflow_event.llm",
            "cost" => { "total" => 0.01 },
            "costStatus" => "imprecise",
            "pricingFreshness" => "snapshot",
            "pricingSource" => "models.dev",
            "activityId" => "abc"
          )

          event = @execution.events.find_by!(event_id: "evt_priced")
          assert_equal "imprecise", event.pricing_status
          assert_equal "snapshot", event.pricing_freshness
          assert_equal "models.dev", event.pricing_source
          assert_equal "abc", event.activity_id
        end

        test "append_event leaves the pricing columns nil when the payload omits them" do
          @execution.append_event(
            "eventId" => "evt_unpriced",
            "action" => "workflow_event.llm",
            "cost" => { "total" => 0.01 }
          )

          event = @execution.events.find_by!(event_id: "evt_unpriced")
          assert_nil event.pricing_status
          assert_nil event.pricing_freshness
          assert_nil event.pricing_source
          assert_nil event.activity_id
        end

        test "rejects an unknown action_type" do
          event = @execution.events.build(
            event_id: "e_bad", action_type: "telepathy",
            workflow_name: "wf", occurred_at: Time.current.utc
          )
          refute event.valid?
          assert event.errors[:action_type].present?
        end
      end
    end
  end
end
