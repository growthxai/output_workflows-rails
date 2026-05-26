# frozen_string_literal: true

require "test_helper"

module OutputWorkflows
  module Responses
    class WorkflowHistoryTest < Minitest::Test
      # --- Long-struct normalization on event attribute payloads ----------------

      def test_normalizes_initiated_event_id_long_struct_to_string
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventId"   => "5",
              "eventType" => "EVENT_TYPE_CHILD_WORKFLOW_EXECUTION_STARTED",
              "childWorkflowExecutionStartedEventAttributes" => {
                "initiatedEventId" => { "low" => 11, "high" => 0, "unsigned" => false }
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["childWorkflowExecutionStartedEventAttributes"]

        assert_equal "11", attrs["initiatedEventId"]
      end

      def test_passes_string_event_ids_through_unchanged
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_ACTIVITY_TASK_COMPLETED",
              "activityTaskCompletedEventAttributes" => {
                "scheduledEventId" => "11",
                "startedEventId"   => "12"
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["activityTaskCompletedEventAttributes"]

        assert_equal "11", attrs["scheduledEventId"]
        assert_equal "12", attrs["startedEventId"]
      end

      def test_normalizes_multiple_event_id_fields_in_one_event
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_CHILD_WORKFLOW_EXECUTION_COMPLETED",
              "childWorkflowExecutionCompletedEventAttributes" => {
                "initiatedEventId" => { "low" => 11, "high" => 0, "unsigned" => false },
                "startedEventId"   => { "low" => 12, "high" => 0, "unsigned" => false },
                "workflowTaskCompletedEventId" => { "low" => 7, "high" => 0, "unsigned" => false }
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["childWorkflowExecutionCompletedEventAttributes"]

        assert_equal "11", attrs["initiatedEventId"]
        assert_equal "12", attrs["startedEventId"]
        assert_equal "7",  attrs["workflowTaskCompletedEventId"]
      end

      def test_normalizes_long_struct_with_high_bits_to_composed_int64_string
        # low=0, high=1 → (1 << 32) = 4_294_967_296
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_CHILD_WORKFLOW_EXECUTION_STARTED",
              "childWorkflowExecutionStartedEventAttributes" => {
                "initiatedEventId" => { "low" => 0, "high" => 1, "unsigned" => false }
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["childWorkflowExecutionStartedEventAttributes"]

        assert_equal "4294967296", attrs["initiatedEventId"]
      end

      def test_event_without_attribute_payload_does_not_raise
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            { "eventId" => "1", "eventType" => "EVENT_TYPE_WORKFLOW_EXECUTION_STARTED" }
          ]
        }

        history = WorkflowHistory.from_hash(hash)

        assert_equal 1, history.events.length
        assert_equal "EVENT_TYPE_WORKFLOW_EXECUTION_STARTED", history.events.first["eventType"]
      end

      def test_leaves_non_event_id_fields_alone
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_CHILD_WORKFLOW_EXECUTION_STARTED",
              "childWorkflowExecutionStartedEventAttributes" => {
                "initiatedEventId" => { "low" => 11, "high" => 0, "unsigned" => false },
                "workflowExecution" => { "workflowId" => "wf_child", "runId" => "run_child" }
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["childWorkflowExecutionStartedEventAttributes"]

        assert_equal "11", attrs["initiatedEventId"]
        assert_equal({ "workflowId" => "wf_child", "runId" => "run_child" }, attrs["workflowExecution"])
      end

      def test_passes_integer_event_ids_through_unchanged
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_ACTIVITY_TASK_STARTED",
              "activityTaskStartedEventAttributes" => {
                "scheduledEventId" => 11
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["activityTaskStartedEventAttributes"]

        assert_equal 11, attrs["scheduledEventId"]
      end

      def test_passes_nil_event_ids_through_unchanged
        hash = {
          "workflow" => { "runId" => "run_abc" },
          "events"   => [
            {
              "eventType" => "EVENT_TYPE_ACTIVITY_TASK_STARTED",
              "activityTaskStartedEventAttributes" => {
                "scheduledEventId" => nil
              }
            }
          ]
        }

        history = WorkflowHistory.from_hash(hash)
        attrs = history.events.first["activityTaskStartedEventAttributes"]

        assert_nil attrs["scheduledEventId"]
      end

      # --- Existing surface area ------------------------------------------------

      def test_from_hash_assigns_workflow_run_id_and_next_page_token
        hash = {
          "workflow"      => { "workflowId" => "wf_abc", "runId" => "run_abc" },
          "events"        => [],
          "nextPageToken" => "tok_1"
        }

        history = WorkflowHistory.from_hash(hash)

        assert_equal({ "workflowId" => "wf_abc", "runId" => "run_abc" }, history.workflow)
        assert_equal "run_abc", history.run_id
        assert_equal "tok_1", history.next_page_token
        assert_equal [], history.events
      end

      def test_handles_missing_events_key_gracefully
        history = WorkflowHistory.from_hash({ "workflow" => { "runId" => "run_abc" } })

        assert_equal [], history.events
      end
    end
  end
end
