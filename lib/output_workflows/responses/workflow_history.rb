# frozen_string_literal: true

module OutputWorkflows
  module Responses
    class WorkflowHistory
      attr_reader :workflow, :events, :run_id, :next_page_token

      def initialize(workflow: nil, events: [], run_id: nil, next_page_token: nil)
        @workflow = workflow
        @events = events || []
        @run_id = run_id
        @next_page_token = next_page_token
      end

      def self.from_hash(hash)
        new(
          workflow:        hash["workflow"],
          events:          hash["events"],
          run_id:          hash.dig("workflow", "runId"),
          next_page_token: hash["nextPageToken"]
        )
      end

      def to_h
        {
          workflow:        workflow,
          events:          events,
          run_id:          run_id,
          next_page_token: next_page_token
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
