# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe QuantRb::Logging do
  around do |example|
    original_logger = QuantRb.logger
    original_level = QuantRb.config.log_level

    begin
      example.run
    ensure
      QuantRb.logger = original_logger
      QuantRb.configure { |config| config.log_level = original_level }
    end
  end

  it "builds a logger with the requested log level" do
    output = StringIO.new
    QuantRb.logger = described_class.build_logger(output: output, level: :warn)

    QuantRb.logger.info("hidden")
    QuantRb.logger.warn("visible")

    expect(output.string).to include("WARN: visible")
    expect(output.string).not_to include("INFO: hidden")
  end

  it "applies config log level changes to the shared logger" do
    output = StringIO.new
    QuantRb.logger = described_class.build_logger(output: output, level: :info)

    QuantRb.configure { |config| config.log_level = :error }
    QuantRb.logger.warn("hidden")
    QuantRb.logger.error("visible")

    expect(output.string).to include("ERROR: visible")
    expect(output.string).not_to include("WARN: hidden")
  end
end
