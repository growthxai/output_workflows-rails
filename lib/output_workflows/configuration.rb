# frozen_string_literal: true

module OutputWorkflows
  class Configuration
    attr_accessor :api_url, :api_key, :webhook_secret,
                  :default_timeout, :default_poll_interval,
                  :job_queue, :table_name, :max_progress_entries

    def initialize
      @api_url = ENV["OUTPUT_API_URL"] || ENV["FLOW_API_BASE_URL"] || default_api_url
      @api_key = ENV["OUTPUT_API_KEY"] || ENV["FLOW_API_KEY"]
      @webhook_secret = ENV["OUTPUT_WEBHOOK_SECRET"] || ENV["FLOW_WEBHOOK_SECRET"]
      @default_timeout = 300 # 5 minutes
      @default_poll_interval = 5 # 5 seconds
      @job_queue = :default
      @table_name = "output_workflow_executions"
      @max_progress_entries = 100
    end

    def validate!
      raise OutputWorkflows::ConfigurationError, "api_url is required" if api_url.nil? || api_url.empty?
    end

    private

    def default_api_url
      return "http://localhost:2000" if defined?(::Rails) && (::Rails.env.development? || ::Rails.env.test?)

      nil
    end
  end
end
