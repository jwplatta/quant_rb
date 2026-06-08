# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::OptionExpiration do
  it "converts an expiration date to a UTC cutoff using New York market close" do
    cutoff = described_class.expiration_time_utc(Date.new(2026, 4, 10))

    expect(cutoff).to eq(Time.utc(2026, 4, 10, 20, 0, 0))
  end

  it "treats timestamps before the cutoff as active and after the cutoff as expired" do
    expiry = Date.new(2026, 4, 10)

    expect(described_class.active?(expiry, Time.utc(2026, 4, 10, 19, 59, 59))).to be(true)
    expect(described_class.expired?(expiry, Time.utc(2026, 4, 10, 19, 59, 59))).to be(false)
    expect(described_class.active?(expiry, Time.utc(2026, 4, 10, 20, 0, 0))).to be(false)
    expect(described_class.expired?(expiry, Time.utc(2026, 4, 10, 20, 0, 0))).to be(true)
  end
end
