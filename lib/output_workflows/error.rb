# frozen_string_literal: true

module OutputWorkflows
  # Base error class for all OutputWorkflows errors
  class Error < StandardError
  end

  # Raised when API request fails
  class APIError < Error
    attr_reader :response_status, :response_body

    def initialize(message, response_status: nil, response_body: nil)
      @response_status = response_status
      @response_body = response_body
      super(message)
    end
  end

  # Raised when workflow times out
  class TimeoutError < Error
  end

  # Raised when workflow is not found
  class WorkflowNotFoundError < Error
  end

  # Raised when workflow fails
  class WorkflowFailedError < Error
    attr_reader :workflow_id, :status_name

    def initialize(message, workflow_id: nil, status_name: nil)
      @workflow_id = workflow_id
      @status_name = status_name
      super(message)
    end
  end

  # Raised when configuration is invalid
  class ConfigurationError < Error
  end
end
