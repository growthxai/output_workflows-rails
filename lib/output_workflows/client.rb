# frozen_string_literal: true

require "faraday"

module OutputWorkflows
  class Client
    attr_reader :configuration

    def initialize(api_url: nil, api_key: nil, **options)
      @configuration = OutputWorkflows.configuration.dup
      @configuration.api_url = api_url if api_url
      @configuration.api_key = api_key if api_key
      @configuration.validate!
    end

    # Start a workflow asynchronously
    # Returns workflow_id string
    def start_workflow(workflow_name, input = {}, **options)
      params = build_workflow_params(workflow_name, input, **options)
      response = connection.post("/workflow/start", params)

      workflow_id = response.body["workflowId"]
      raise APIError.new("No workflowId returned", response_body: response.body) unless workflow_id

      workflow_id
    rescue Faraday::Error => e
      handle_faraday_error("start workflow #{workflow_name}", e)
    end

    # Get workflow status
    # Returns OutputWorkflows::Responses::Status or nil if not found
    def workflow_status(workflow_id)
      response = connection.get("/workflow/#{workflow_id}/status")
      OutputWorkflows::Responses::Status.from_hash(response.body)
    rescue Faraday::ResourceNotFound
      nil
    rescue Faraday::Error => e
      handle_faraday_error("get status for workflow #{workflow_id}", e)
    end

    # Get workflow result
    # Returns OutputWorkflows::Responses::WorkflowResult
    def workflow_result(workflow_id)
      response = connection.get("/workflow/#{workflow_id}/result")
      OutputWorkflows::Responses::WorkflowResult.from_hash(response.body)
    rescue Faraday::Error => e
      handle_faraday_error("get result for workflow #{workflow_id}", e)
    end

    # Cancel/stop a running workflow
    # Returns true if cancelled successfully, false if workflow doesn't exist
    # PATCH /workflow/{workflow_id}/stop
    def cancel_workflow(workflow_id)
      connection.patch("/workflow/#{workflow_id}/stop")
      true # Successfully cancelled
    rescue Faraday::ResourceNotFound, Faraday::ClientError => e
      # 404/410 means workflow doesn't exist or already stopped - idempotent
      status = e.response_status if e.respond_to?(:response_status)
      if [404, 410].include?(status)
        log_info("Workflow #{workflow_id} already stopped (#{status})")
        false # Already stopped
      else
        raise
      end
    rescue Faraday::Error => e
      handle_faraday_error("cancel workflow #{workflow_id}", e)
    end

    # Wait for workflow completion by polling status
    # Returns OutputWorkflows::Responses::WorkflowResult on success
    # Raises TimeoutError if timeout exceeded
    # Raises WorkflowFailedError if workflow fails
    def wait_for_completion(workflow_id, poll_interval: nil, timeout: nil)
      poll_interval ||= configuration.default_poll_interval
      timeout ||= configuration.default_timeout
      start_time = Time.now

      loop do
        elapsed = Time.now - start_time
        if elapsed > timeout
          raise TimeoutError, "Workflow #{workflow_id} timed out after #{timeout} seconds"
        end

        status_response = workflow_status(workflow_id)
        raise WorkflowNotFoundError, "Workflow #{workflow_id} not found" unless status_response

        if status_response.completed?
          return workflow_result(workflow_id)
        elsif status_response.failed?
          raise WorkflowFailedError.new(
            "Workflow #{workflow_id} failed with status: #{status_response.status_name}",
            workflow_id: workflow_id,
            status_name: status_response.status_name
          )
        end

        # Still running, sleep and try again
        sleep poll_interval
      end
    end

    # HTTP connection
    def connection
      @connection ||= Faraday.new(url: configuration.api_url) do |faraday|
        faraday.request :json
        faraday.headers["Authorization"] = "Basic #{configuration.api_key}" if configuration.api_key
        faraday.response :json
        faraday.response :raise_error
        if defined?(::Rails) && ::Rails.env.development?
          faraday.response :logger, nil, { headers: true, bodies: true, errors: true }
        end
        faraday.adapter Faraday.default_adapter
      end
    end

    private

    def build_workflow_params(workflow_name, input, **options)
      params = {
        workflow_name: workflow_name,
        input: input
      }

      # Add task_queue in production
      if defined?(::Rails) && ::Rails.env.production?
        params[:task_queue] = options[:task_queue] || "internal-low-priority"
      end

      # Convert keys to camelCase for API
      deep_transform_keys_to_camel_case(params)
    end

    def deep_transform_keys_to_camel_case(hash)
      hash.each_with_object({}) do |(key, value), result|
        new_key = key.to_s.gsub(/_([a-z])/) { ::Regexp.last_match(1).upcase }
        new_value = value.is_a?(Hash) ? deep_transform_keys_to_camel_case(value) : value
        result[new_key] = new_value
      end
    end

    def handle_faraday_error(action, error)
      status = error.response_status if error.respond_to?(:response_status)
      body = error.response_body if error.respond_to?(:response_body)

      raise OutputWorkflows::APIError.new(
        "Failed to #{action}: #{error.message}",
        response_status: status,
        response_body: body
      )
    end

    def log_info(message)
      if defined?(::Rails)
        ::Rails.logger.info(message)
      end
    end
  end
end
