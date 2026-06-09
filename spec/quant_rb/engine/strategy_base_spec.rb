# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::StrategyBase do
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
        @spy = add_security("SPY", resolution: :minute)
        @spxw = add_option_chain("SPX", "SPXW", resolution: :minute)
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
    expect(strategy.subscribed_option_chains[:SPXW_options][:chain_mode]).to be_nil
    expect(strategy.subscribed_securities[:SPY]).to eq(symbol: "SPY", resolution: :minute, kind: :security)
  end

  it "normalizes synthetic and interpolated option-chain modes into canonical config" do
    strategy_class = Class.new(described_class) do
      attr_reader :synthetic_key, :interpolated_key

      def initialize
        @synthetic_key = add_option_chain("SPX", "SPXW_SYN", synthetic: true, iv: { "0DTE" => "VIX1D", "9DTE" => "VIX9D", "30DTE" => "VIX" })
        @interpolated_key = add_option_chain("SPX", "SPXW_INT", interpolate: true)
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    subscriptions = strategy.subscribed_option_chains
    expect(subscriptions[strategy.synthetic_key][:chain_mode]).to eq(:synthetic)
    expect(subscriptions[strategy.interpolated_key][:chain_mode]).to eq(:sampled_interpolated)
  end

  it "preserves explicit raw option config for interpolated chains" do
    strategy_class = Class.new(described_class) do
      attr_reader :interpolated_key

      def initialize
        @interpolated_key = add_option_chain(
          "SPX",
          "SPXW_INT",
          dataset: "massive_samples",
          interpolate: true,
          raw_options: { bucket_selector: :first }
        )
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    subscription = strategy.subscribed_option_chains[strategy.interpolated_key]
    expect(subscription[:dataset]).to eq("massive_samples")
    expect(subscription[:raw_options][:bucket_selector]).to eq(:first)
  end

  it "propagates the strategy market timezone into option chain subscriptions" do
    strategy_class = Class.new(described_class) do
      attr_reader :option_key

      def initialize
        set_market_timezone("America/Chicago")
        @option_key = add_option_chain("SPX", "SPXW")
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    expect(strategy.market_timezone).to eq("America/Chicago")
    expect(strategy.subscribed_option_chains[strategy.option_key][:market_timezone]).to eq("America/Chicago")
  end

  it "registers indices separately from tradable securities" do
    strategy_class = Class.new(described_class) do
      attr_reader :spx

      def initialize
        @spx = add_index("SPX", resolution: :"5min")
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    expect(strategy.subscribed_indices[:SPX]).to eq(symbol: "SPX", resolution: :"5min", kind: :index)
    expect(strategy.subscribed_underlyings[:SPX][:kind]).to eq(:index)
  end

  it "exposes market_date from the localized runtime timestamp" do
    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )
    strategy.send(:set_time, Time.parse("2024-01-15 10:00:00 -0500"))

    expect(strategy.market_time).to eq(Time.parse("2024-01-15 10:00:00 -0500"))
    expect(strategy.market_date).to eq(Date.new(2024, 1, 15))
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

  it "rejects direct index share orders" do
    strategy_class = Class.new(described_class) do
      def initialize
        add_index("SPX")
      end
    end

    strategy = strategy_class.build_for_engine(
      portfolio: portfolio,
      schedule: schedule,
      securities: securities,
      broker: broker
    )

    expect { strategy.market_order(:SPX, 1) }.to raise_error(ArgumentError, /cannot be traded/)
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
