# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Reporting::ProgressReporter do
  let(:output) { instance_double(IO, tty?: tty_output) }
  let(:tty_output) { true }

  it "creates a progress bar in auto mode when output is a tty" do
    progress_bar = double("ProgressBar")

    expect(ProgressBar).to receive(:create).with(
      total: 10,
      title: "Example",
      format: "%t |%B| %c/%C %p%% %e"
    ).and_return(progress_bar)

    reporter = described_class.new(total: 10, title: "Example", output: output)

    expect(reporter.enabled).to be(true)
  end

  it "stays disabled in auto mode when output is not a tty" do
    allow(output).to receive(:tty?).and_return(false)
    reporter = described_class.new(total: 10, title: "Example", output: output)

    expect(reporter.enabled).to be(false)
  end

  it "allows callers to force-disable progress output" do
    reporter = described_class.new(total: 10, title: "Example", enabled: false, output: output)

    expect(reporter.enabled).to be(false)
  end

  it "allows callers to force-enable progress output" do
    progress_bar = double("ProgressBar")
    expect(ProgressBar).to receive(:create).and_return(progress_bar)

    reporter = described_class.new(total: 10, title: "Example", enabled: true, output: output)

    expect(reporter.enabled).to be(true)
  end

  it "raises on invalid progress settings" do
    expect do
      described_class.new(total: 10, title: "Example", enabled: :sometimes, output: output)
    end.to raise_error(ArgumentError, /progress must be :auto, true, or false/)
  end
end
