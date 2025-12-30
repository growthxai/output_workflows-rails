# frozen_string_literal: true

require_relative "lib/output_workflows/version"

Gem::Specification.new do |spec|
  spec.name = "output_workflows-rails"
  spec.version = OutputWorkflows::VERSION
  spec.authors = ["GrowthX"]
  spec.email = ["dev@growthx.ai"]

  spec.summary = "Rails SDK for Output.ai AI workflows"
  spec.description = "Rails SDK for Output.ai AI workflows. " \
                     "Supports synchronous and asynchronous workflow execution, progress tracking, " \
                     "and webhook verification."
  spec.homepage = "https://github.com/growthx/output_workflows-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/growthx/output_workflows-rails"
  spec.metadata["changelog_uri"] = "https://github.com/growthx/output_workflows-rails/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,sig}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"].reject do |f|
      File.directory?(f) || f.start_with?(".")
    end
  end
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-net_http"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
