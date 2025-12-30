# frozen_string_literal: true

module OutputWorkflows
  module Rails
  end
end

require_relative "rails/railtie" if defined?(::Rails::Railtie)
