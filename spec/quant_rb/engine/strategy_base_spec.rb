# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::StrategyBase do
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
end
