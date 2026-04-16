# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Brokers::IbBroker do
  let(:broker) { described_class.new(host: "localhost", port: 4002, client_id: 7) }

  it "retains constructor configuration for future live wiring" do
    expect(broker.host).to eq("localhost")
    expect(broker.port).to eq(4002)
    expect(broker.client_id).to eq(7)
  end

  it "exposes the broker adapter methods as explicit stubs" do
    expect { broker.submit_order(:order) }.to raise_error(NotImplementedError, /live order submission/)
    expect { broker.cancel_order("1") }.to raise_error(NotImplementedError, /live order cancellation/)
    expect { broker.process_pending_orders(:slice, :portfolio) }.to raise_error(NotImplementedError, /live order processing/)
    expect { broker.get_quotes([:SPY]) }.to raise_error(NotImplementedError, /quote retrieval/)
  end
end
