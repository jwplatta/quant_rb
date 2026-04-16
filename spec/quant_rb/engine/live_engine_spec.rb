# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::LiveEngine do
  let(:broker) { instance_double(QuantRb::Brokers::BrokerAdapter) }
  let(:data_feed) { Object.new }
  let(:clock) { Object.new }

  it "captures the configured live execution dependencies" do
    engine = described_class.new(
      strategy_class: QuantRb::Strategy,
      broker: broker,
      data_feed: data_feed,
      clock: clock
    )

    expect(engine.strategy_class).to eq(QuantRb::Strategy)
    expect(engine.broker).to eq(broker)
    expect(engine.data_feed).to eq(data_feed)
    expect(engine.clock).to eq(clock)
  end

  it "raises a clear error when run is attempted" do
    engine = described_class.new(strategy_class: QuantRb::Strategy, broker: broker)

    expect { engine.run }.to raise_error(NotImplementedError, /Phase 7 stub/)
  end

  it "exposes the same class-level run entry point shape as BacktestEngine" do
    expect do
      described_class.run(QuantRb::Strategy, broker: broker)
    end.to raise_error(NotImplementedError, /paper\/live execution/)
  end
end
