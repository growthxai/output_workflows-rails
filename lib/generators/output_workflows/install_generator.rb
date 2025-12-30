# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module OutputWorkflows
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        if ActiveRecord::Base.timestamped_migrations
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        else
          "%.3d" % (current_migration_number(dirname) + 1)
        end
      end

      def create_migration
        migration_template(
          "create_output_workflow_executions.rb.erb",
          "db/migrate/create_output_workflow_executions.rb"
        )
      end

      def create_initializer
        template "output_workflows.rb.erb", "config/initializers/output_workflows.rb"
      end

      def show_instructions
        say ""
        say "OutputWorkflows installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations: rails db:migrate"
        say "  2. Configure API credentials in config/initializers/output_workflows.rb"
        say "  3. Set OUTPUT_API_URL and OUTPUT_API_KEY environment variables"
        say ""
      end
    end
  end
end
