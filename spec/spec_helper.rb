# frozen_string_literal: true

require "securerandom"
require_relative "../lib/quant_rb"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"

  # Integration tests require local tickrake data — skip unless INTEGRATION=1
  config.filter_run_excluding :integration unless ENV["INTEGRATION"] == "1"
end
