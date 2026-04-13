# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::Scheduler do
  let(:scheduler) { described_class.new }
  let(:date_rules) { QuantRb::Engine::DateRules.new }
  let(:time_rules) { QuantRb::Engine::TimeRules.new }
  let(:callback) { instance_double(Proc) }
  let(:matching_time) { Time.parse("2024-01-15 15:00:00 UTC") }

  it "fires callbacks when both rules match" do
    allow(callback).to receive(:call)

    scheduler.on(date_rules.every_day(:SPY), time_rules.at(15, 0), callback)
    scheduler.fire(matching_time)

    expect(callback).to have_received(:call).once
  end

  it "does not refire the same event for the same timestamp" do
    allow(callback).to receive(:call)

    scheduler.on(date_rules.every_day(:SPY), time_rules.at(15, 0), callback)
    2.times { scheduler.fire(matching_time) }

    expect(callback).to have_received(:call).once
  end

  it "supports market open offsets" do
    allow(callback).to receive(:call)

    scheduler.on(date_rules.every_day(:SPY), time_rules.market_open(offset_minutes: 5), callback)
    scheduler.fire(Time.parse("2024-01-15 09:35:00 UTC"))

    expect(callback).to have_received(:call).once
  end
end
