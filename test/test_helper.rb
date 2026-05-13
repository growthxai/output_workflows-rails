# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "output_workflows"

require "minitest/autorun"
require "webmock/minitest"

# Default to a known test URL so Configuration#validate! passes everywhere.
OutputWorkflows.configure do |config|
  config.api_url = "http://test.local"
end
