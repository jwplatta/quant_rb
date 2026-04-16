# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Brokers::SchwabBroker do
  let(:broker) { described_class.new(account_name: "paper", schwab_client: :client) }

  it "retains constructor configuration for future live wiring" do
    expect(broker.account_name).to eq("paper")
    expect(broker.schwab_client).to eq(:client)
  end

  it "exposes the broker adapter methods as explicit stubs" do
    expect { broker.submit_order(:order) }.to raise_error(NotImplementedError, /live order submission/)
    expect { broker.cancel_order("1") }.to raise_error(NotImplementedError, /live order cancellation/)
    expect { broker.process_pending_orders(:slice, :portfolio) }.to raise_error(NotImplementedError, /live order processing/)
    expect { broker.get_quotes([:SPY]) }.to raise_error(NotImplementedError, /quote retrieval/)
  end
end
