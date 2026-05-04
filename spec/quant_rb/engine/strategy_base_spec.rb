# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::StrategyBase do
  around do |example|
    original_logger = QuantRb.logger
    begin
      example.run
    ensure
      QuantRb.logger = original_logger
    end
  end

  let(:portfolio) { QuantRb::Engine::Portfolio.new(initial_cash: 50_000) }
  let(:schedule) { QuantRb::Engine::Scheduler.new }
  let(:securities) { QuantRb::Engine::Securities.new }
  let(:broker) do
    instance_double(
      QuantRb::Brokers::BacktestBroker,
      submit_order: QuantRb::Engine::OrderTicket.new(order_id: "1", status: :submitted)
    )
  end

  let(:strategy_class) do
    Class.new(described_class) do
      attr_reader :spy, :spxw

      def initialize
        set_start_date(2024, 1, 1)
        set_end_date(2024, 12, 31)
        set_cash(125_000)
        @spy = add_equity("SPY", resolution: :minute)
        @spxw = add_index_option("SPX", "SPXW", resolution: :minute)
      end
    end
  end

  it "builds a strategy with injected dependencies before initialize runs" do
    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    expect(strategy.portfolio).to eq(portfolio)
    expect(strategy.schedule).to eq(schedule)
    expect(strategy.broker).to eq(broker)
    expect(strategy.spy).to eq(:SPY)
    expect(strategy.spxw).to eq(:SPXW_options)
    expect(strategy.initial_cash).to eq(125_000)
    expect(strategy.subscribed_option_chain_symbols[:SPXW_options][:config].chain_mode).to eq(:sampled_validated)
  end

  it "normalizes synthetic and interpolated option-chain modes into canonical config" do
    strategy_class = Class.new(described_class) do
      attr_reader :synthetic_key, :interpolated_key

      def initialize
        @synthetic_key = add_index_option("SPX", "SPXW_SYN", provider: "test", synthetic: true, iv: { "0DTE" => "VIX1D", "9DTE" => "VIX9D", "30DTE" => "VIX" })
        @interpolated_key = add_index_option("SPX", "SPXW_INT", provider: "test", interpolate: true)
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    subscriptions = strategy.subscribed_option_chain_symbols
    expect(subscriptions[strategy.synthetic_key][:config].chain_mode).to eq(:synthetic)
    expect(subscriptions[strategy.interpolated_key][:config].chain_mode).to eq(:sampled_interpolated)
  end

  it "preserves explicit raw option config for interpolated chains" do
    strategy_class = Class.new(described_class) do
      attr_reader :interpolated_key

      def initialize
        @interpolated_key = add_index_option(
          "SPX",
          "SPXW_INT",
          provider: "massive",
          interpolate: true,
          raw_options: { underlying_provider: "ibkr-paper" }
        )
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    config = strategy.subscribed_option_chain_symbols[strategy.interpolated_key][:config]
    expect(config.raw_options[:underlying_provider]).to eq("ibkr-paper")
  end

  it "normalizes debit combo limits to positive prices" do
    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )
    strategy.send(:set_time, Time.parse("2024-01-15 15:00:00 UTC"))

    expect(broker).to receive(:submit_order) do |order|
      expect(order.direction).to eq(:debit)
      expect(order.limit_price).to eq(1.25)
    end.and_return(QuantRb::Engine::OrderTicket.new(order_id: "2", status: :submitted))

    strategy.combo_limit_order([{ symbol: "LEG1", quantity: 1 }, { symbol: "LEG2", quantity: -1 }], 1, -1.25)
  end

  it "routes strategy log levels through the shared quant_rb logger" do
    logger = instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil)
    QuantRb.logger = logger

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )
    strategy.send(:set_time, Time.parse("2024-01-15 15:00:00 UTC"))

    expect(logger).to receive(:info).with(include("[2024-01-15 15:00:00 UTC]"))
    expect(logger).to receive(:debug).with(include("debug message"))
    expect(logger).to receive(:warn).with(include("warn message"))
    expect(logger).to receive(:error).with(include("error message"))

    strategy.log("info message")
    strategy.debug("debug message")
    strategy.warn("warn message")
    strategy.error("error message")
  end
end
