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
          events:          EventNormalizer.call(hash["events"]),
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

      # Normalizes Temporal event payloads coming from the Output JS API.
      #
      # The JS-side serializer stringifies *some* int64 fields (e.g.
      # +scheduledEventId+, +startedEventId+) but leaves others as raw
      # protobuf Long structs of the form:
      #
      #   { "low" => N, "high" => H, "unsigned" => false }
      #
      # The most visible offender is +initiatedEventId+ on every
      # +CHILD_WORKFLOW_EXECUTION_*+ event. This module walks each event,
      # finds its +*EventAttributes+ payload, and converts any field whose
      # name ends in +EventId+ from a Long struct to a String. Strings,
      # integers, and +nil+ pass through unchanged.
      module EventNormalizer
        LONG_STRUCT_KEYS = %w[low high unsigned].freeze
        EVENT_ID_SUFFIX = "EventId"
        ATTRIBUTES_SUFFIX = "EventAttributes"

        def self.call(events)
          return [] if events.nil?

          events.map { |event| normalize_event(event) }
        end

        def self.normalize_event(event)
          return event unless event.is_a?(Hash)

          event.each_with_object({}) do |(key, value), acc|
            acc[key] =
              if key.end_with?(ATTRIBUTES_SUFFIX) && value.is_a?(Hash)
                normalize_attributes(value)
              else
                value
              end
          end
        end

        def self.normalize_attributes(attributes)
          attributes.each_with_object({}) do |(key, value), acc|
            acc[key] =
              if key.end_with?(EVENT_ID_SUFFIX)
                normalize_event_id(value)
              else
                value
              end
          end
        end

        def self.normalize_event_id(value)
          return value unless long_struct?(value)

          low = value["low"].to_i
          high = value["high"].to_i
          # Compose the signed 64-bit value from its low/high 32-bit halves.
          # Mask each half to 32 bits so negative ints don't sign-extend.
          composed = ((high & 0xFFFFFFFF) << 32) | (low & 0xFFFFFFFF)
          composed.to_s
        end

        def self.long_struct?(value)
          value.is_a?(Hash) && LONG_STRUCT_KEYS.all? { |k| value.key?(k) }
        end
      end
      private_constant :EventNormalizer
    end
  end
end
