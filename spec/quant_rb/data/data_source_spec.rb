# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::DataSource do
  around do |example|
    original_config = QuantRb.config.dup

    QuantRb.configure do |config|
      config.data_path = "/tmp/quant_rb_data"
      config.options_subpath = "options/custom"
      config.history_subpath = "history/custom"
    end

    example.run
  ensure
    QuantRb.instance_variable_set(:@config, original_config)
  end

  it "builds the configured options path" do
    expect(described_class.options_path).to eq("/tmp/quant_rb_data/options/custom")
  end

  it "builds the configured history path" do
    expect(described_class.history_path).to eq("/tmp/quant_rb_data/history/custom")
  end
end
