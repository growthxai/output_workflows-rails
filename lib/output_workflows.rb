# frozen_string_literal: true

require_relative "output_workflows/version"
require_relative "output_workflows/error"
require_relative "output_workflows/configuration"
require_relative "output_workflows/responses/status"
require_relative "output_workflows/responses/workflow_result"
require_relative "output_workflows/client"
require_relative "output_workflows/webhook_verifier"

# Rails integration - loaded via railtie
require_relative "output_workflows/rails" if defined?(::Rails)

module OutputWorkflows
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Convenience method to create a client with default configuration
    def client
      @client ||= Client.new
    end

    # Reset configuration (useful for testing)
    def reset_configuration!
      @configuration = nil
      @client = nil
    end
  end
end
