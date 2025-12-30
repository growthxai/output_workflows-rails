# frozen_string_literal: true

module OutputWorkflows
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "output_workflows.load_rails_components" do
        require_relative "workflow_execution"
        require_relative "status_check_job"
        require_relative "webhook_processor"
        require_relative "progress_processor"
      end
    end
  end
end
