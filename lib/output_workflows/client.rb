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
    #
    # When `run_id` is provided, hits the run-scoped endpoint
    # (`/workflow/{id}/runs/{rid}/result`) so callers pin the result to a
    # specific run. This matters under retries / continue-as-new where multiple
    # runs can share a `workflow_id`. Falls back to the un-pinned latest-run
    # endpoint when `run_id` is nil.
    def workflow_result(workflow_id, run_id: nil)
      path = run_id ? "/workflow/#{workflow_id}/runs/#{run_id}/result" : "/workflow/#{workflow_id}/result"
      response = connection.get(path)
      OutputWorkflows::Responses::WorkflowResult.from_hash(response.body)
    rescue Faraday::Error => e
      handle_faraday_error("get result for workflow #{workflow_id}#{run_id ? " run #{run_id}" : ""}", e)
    end

    # Get a single page of workflow history events.
    #
    # When `run_id` is provided, hits `/workflow/{id}/runs/{rid}/history` so
    # callers pin the history to a specific run. Without `run_id`, hits the
    # latest-run endpoint at `/workflow/{id}/history`.
    #
    # `page_token` (base64 cursor) drives pagination — the caller paginates by
    # re-calling with each `next_page_token` until it comes back nil. The
    # upstream API requires `run_id` when `page_token` is supplied.
    #
    # `include_payloads` (default false) toggles whether step inputs, outputs,
    # and failure details are inlined in events. Defaults to false for the
    # lightweight polling path; opt in for one-shot inspection of completed
    # runs.
    #
    # Returns OutputWorkflows::Responses::WorkflowHistory.
    def workflow_history(workflow_id, run_id: nil, page_size: 50, page_token: nil, include_payloads: false)
      path = run_id ? "/workflow/#{workflow_id}/runs/#{run_id}/history" : "/workflow/#{workflow_id}/history"
      params = { pageSize: page_size, includePayloads: include_payloads }
      params[:pageToken] = page_token if page_token

      response = connection.get(path, params)
      OutputWorkflows::Responses::WorkflowHistory.from_hash(response.body)
    rescue Faraday::Error => e
      handle_faraday_error("get history for workflow #{workflow_id}#{run_id ? " run #{run_id}" : ""}", e)
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
    #
    # `run_id` is plumbed through to `workflow_result` so the final result
    # fetch can be pinned to a specific run when known.
    def wait_for_completion(workflow_id, poll_interval: nil, timeout: nil, run_id: nil)
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
          return workflow_result(workflow_id, run_id: run_id)
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

      # Add task_queue if explicitly provided
      params[:task_queue] = options[:task_queue] if options[:task_queue]

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
