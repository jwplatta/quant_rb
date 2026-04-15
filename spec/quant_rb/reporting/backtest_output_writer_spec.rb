# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe QuantRb::Reporting::BacktestOutputWriter do
  let(:trade) do
    QuantRb::Reporting::TradeRecord.new(
      id: "trade-1",
      strategy_class: "TestStrategy",
      symbol: "SPY",
      direction: :long,
      quantity: 1,
      entry_price: 100.0,
      exit_price: 102.0,
      entry_time: Time.parse("2024-01-02 14:31:00 UTC"),
      exit_time: Time.parse("2024-01-02 14:32:00 UTC"),
      legs: [{ symbol: :SPY, quantity: 1 }],
      notes: "test trade"
    )
  end

  let(:result) do
    QuantRb::Reporting::BacktestResult.new(
      strategy_class: "TestStrategy",
      start_date: Date.new(2024, 1, 2),
      end_date: Date.new(2024, 1, 2),
      initial_cash: 10_000,
      final_portfolio_value: 10_002,
      trades: [trade]
    )
  end

  it "writes summary and trades csv files with an explicit base name" do
    Dir.mktmpdir do |dir|
      paths = described_class.new(result, output_dir: dir, name: "demo_run").save

      expect(paths[:summary_path]).to eq(File.join(dir, "demo_run_summary.csv"))
      expect(paths[:trades_path]).to eq(File.join(dir, "demo_run_trades.csv"))
      expect(File.read(paths[:summary_path])).to include("field,value", "strategy_class,TestStrategy")
      expect(File.read(paths[:trades_path])).to include("trade-1", "test trade")
    end
  end

  it "generates a unique base name when one is not provided" do
    Dir.mktmpdir do |dir|
      paths = described_class.new(result, output_dir: dir).save

      expect(File.basename(paths[:summary_path])).to match(/\A[a-f0-9]{12}_summary\.csv\z/)
      expect(File.basename(paths[:trades_path])).to match(/\A[a-f0-9]{12}_trades\.csv\z/)
    end
  end

  it "writes json summary and trades files when requested" do
    Dir.mktmpdir do |dir|
      paths = described_class.new(result, output_dir: dir, format: :json, name: "json_run").save

      expect(paths[:summary_path]).to end_with("json_run_summary.json")
      expect(paths[:trades_path]).to end_with("json_run_trades.json")
      expect(File.read(paths[:summary_path])).to include("\"strategy_class\": \"TestStrategy\"")
      expect(File.read(paths[:trades_path])).to include("\"id\": \"trade-1\"")
    end
  end

  it "sanitizes provided names for filesystem-safe output" do
    Dir.mktmpdir do |dir|
      paths = described_class.new(result, output_dir: dir, name: "my demo/run").save

      expect(File.basename(paths[:summary_path])).to eq("my_demo_run_summary.csv")
      expect(File.basename(paths[:trades_path])).to eq("my_demo_run_trades.csv")
    end
  end
end
