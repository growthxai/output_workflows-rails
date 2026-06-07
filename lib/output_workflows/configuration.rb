# frozen_string_literal: true

module OutputWorkflows
  class Configuration
    attr_accessor :api_url, :api_key, :webhook_secret,
                  :default_timeout, :default_poll_interval,
                  :request_timeout, :open_timeout,
                  :job_queue, :table_name, :max_progress_entries

    def initialize
      @api_url = ENV["OUTPUT_API_URL"] || ENV["FLOW_API_BASE_URL"] || default_api_url
      @api_key = ENV["OUTPUT_API_KEY"] || ENV["FLOW_API_KEY"]
      @webhook_secret = ENV["OUTPUT_WEBHOOK_SECRET"] || ENV["FLOW_WEBHOOK_SECRET"]
      @default_timeout = 300 # 5 minutes — wait_for_completion polling budget
      @default_poll_interval = 5 # 5 seconds
      # Per-HTTP-request timeouts. Without these a hung API would block the caller
      # indefinitely (and, on the consumer side, hold any lock held across the call).
      @request_timeout = (ENV["OUTPUT_API_REQUEST_TIMEOUT"] || 20).to_i # whole request, seconds
      @open_timeout = (ENV["OUTPUT_API_OPEN_TIMEOUT"] || 5).to_i # connect, seconds
      @job_queue = :default
      @table_name = "output_workflow_executions"
      @max_progress_entries = 100
    end

    def validate!
      raise OutputWorkflows::ConfigurationError, "api_url is required" if api_url.nil? || api_url.empty?
    end

    private
      def default_api_url
        return "http://localhost:3001" if defined?(::Rails) && (::Rails.env.development? || ::Rails.env.test?)

        nil
      end
  end
end
