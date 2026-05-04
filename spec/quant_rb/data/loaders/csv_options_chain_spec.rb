# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe QuantRb::Data::Loaders::CsvOptionsChain do
  around do |example|
    original_logger = QuantRb.logger
    original_config = QuantRb.config.dup
    begin
      example.run
    ensure
      QuantRb.logger = original_logger
      QuantRb.instance_variable_set(:@config, original_config)
    end
  end

  let(:fixture_path) do
    QUANT_RB_FIXTURES_ROOT.join("options", "schwab", "SPXW_exp2025-12-18_2025-12-18_13-50-58.csv")
  end

  describe ".load" do
    it "parses a chain csv into options with greeks and metadata" do
      QuantRb.configure { |config| config.market_timezone = "America/Chicago" }
      chain = described_class.load(fixture_path)

      expect(chain).to be_a(QuantRb::DataObjects::OptionsChain)
      expect(chain.symbol).to eq("SPXW")
      expect(chain.underlying_price).to eq(6005.0)
      expect(chain.call_opts.size).to eq(1)
      expect(chain.put_opts.size).to eq(1)

      call = chain.call_opts.first
      expect(call.symbol).to eq("SPXW  251218C06000000")
      expect(call.underlying_symbol).to eq("SPXW")
      expect(call.delta).to eq(0.44)
      expect(call.gamma).to eq(0.016)
      expect(call.theta).to eq(-0.85)
      expect(call.vega).to eq(1.31)
      expect(call.rho).to eq(0.09)
      expect(call.expiration_date).to eq(Date.new(2025, 12, 18))
      expect(call.days_to_expiration).to eq(0)
      expect(call.timestamp).to eq(Time.utc(2025, 12, 18, 19, 50, 58))
    end

    it "logs malformed rows through QuantRb.logger" do
      logger = instance_double(Logger, warn: nil)
      QuantRb.logger = logger

      Dir.mktmpdir do |dir|
        path = File.join(dir, "SPXW_exp2025-12-18_2025-12-18_13-50-58.csv")
        File.write(path, <<~CSV)
          contract_type,symbol,expiration_date,strike,underlying_price,open_interest,total_volume
          CALL,SPXW  251218C06000000,2025-12-18,6000,6005,not-an-int,10
        CSV

        expect(logger).to receive(:warn).with(include("Skipping malformed option row"))
        chain = described_class.load(path)
        expect(chain.call_opts).to eq([])
        expect(chain.put_opts).to eq([])
      end
    end
  end
end
