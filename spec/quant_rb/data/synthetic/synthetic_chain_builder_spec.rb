# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe QuantRb::Data::Synthetic::SyntheticChainBuilder do
  def candle(timestamp, open:, high:, low:, close:, volume: 1_000)
    QuantRb::DataObjects::Candle.new(
      datetime: Time.parse(timestamp),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    )
  end

  def series(*candles)
    QuantRb::Data::Series::CandleSeries.new(candles)
  end

  let(:spx_series) do
    series(
      candle("2026-04-08T14:30:00Z", open: 5_060, high: 5_085, low: 5_040, close: 5_070),
      candle("2026-04-08T20:00:00Z", open: 5_070, high: 5_095, low: 5_060, close: 5_090),
      candle("2026-04-09T14:30:00Z", open: 5_095, high: 5_110, low: 5_085, close: 5_105),
      candle("2026-04-09T17:00:00Z", open: 5_105, high: 5_125, low: 5_100, close: 5_120)
    )
  end

  let(:vix_series) do
    series(
      candle("2026-04-08T14:30:00Z", open: 18.8, high: 19.0, low: 18.6, close: 18.9),
      candle("2026-04-09T17:00:00Z", open: 18.1, high: 18.5, low: 17.9, close: 18.3)
    )
  end

  let(:vix9d_series) do
    series(
      candle("2026-04-08T14:30:00Z", open: 17.9, high: 18.1, low: 17.7, close: 18.0),
      candle("2026-04-09T17:00:00Z", open: 16.8, high: 17.2, low: 16.6, close: 17.0)
    )
  end

  let(:vix1d_series) do
    series(
      candle("2026-04-08T14:30:00Z", open: 16.9, high: 17.0, low: 16.5, close: 16.7),
      candle("2026-04-09T17:00:00Z", open: 15.8, high: 16.1, low: 15.6, close: 15.9)
    )
  end

  let(:builder) do
    described_class.new(
      spx_series: spx_series,
      vix_series: vix_series,
      vix9d_series: vix9d_series,
      vix1d_series: vix1d_series
    )
  end

  let(:target_time) { Time.parse("2026-04-09T17:00:00Z") }
  let(:expiration_date) { Date.new(2026, 4, 10) }

  describe "#build" do
    it "builds a synthetic call and put surface around spot" do
      chain = builder.build(target_time: target_time, expiration_date: expiration_date, symbol: "SPXW")

      expect(chain.symbol).to eq("SPXW")
      expect(chain.underlying_price).to eq(5_120.0)
      expect(chain.expiration_dates).to eq([expiration_date])
      expect(chain.call_opts.size).to be > 50
      expect(chain.put_opts.size).to eq(chain.call_opts.size)

      atm_call = chain.call_opts.min_by { |option| (option.strike - chain.underlying_price).abs }
      atm_put = chain.put_opts.min_by { |option| (option.strike - chain.underlying_price).abs }

      expect(atm_call.delta).to be_between(0.40, 0.60)
      expect(atm_put.delta).to be_between(-0.60, -0.40)
      expect(atm_call.gamma).not_to be_nil
      expect(atm_call.theta).not_to be_nil
      expect(atm_call.vega).not_to be_nil
      expect(atm_call.rho).not_to be_nil
      expect(atm_call.mark).to be > 0.0
      expect(atm_put.mark).to be > 0.0
      expect(atm_call.bid).to be <= atm_call.ask
      expect(atm_put.bid).to be <= atm_put.ask
    end

    it "produces monotonic call and put prices by strike after no-arbitrage adjustments" do
      chain = builder.build(target_time: target_time, expiration_date: expiration_date, symbol: "SPXW")

      call_marks = chain.call_opts.sort_by(&:strike).map(&:mark)
      put_marks = chain.put_opts.sort_by(&:strike).map(&:mark)

      expect(call_marks.each_cons(2).all? { |left, right| left >= right }).to be(true)
      expect(put_marks.each_cons(2).all? { |left, right| left <= right }).to be(true)
    end

    it "supports binomial pricing mode and still populates greeks" do
      binomial_builder = described_class.new(
        spx_series: spx_series,
        vix_series: vix_series,
        vix9d_series: vix9d_series,
        vix1d_series: vix1d_series,
        pricing_model: :binomial
      )

      chain = binomial_builder.build(target_time: target_time, expiration_date: expiration_date, symbol: "SPXW")
      atm_call = chain.call_opts.min_by { |option| (option.strike - chain.underlying_price).abs }

      expect(atm_call.mark).to be > 0.0
      expect(atm_call.delta).to be_between(0.35, 0.65)
      expect(atm_call.gamma).not_to be_nil
      expect(atm_call.theta).not_to be_nil
      expect(atm_call.vega).not_to be_nil
      expect(atm_call.rho).not_to be_nil
    end

    it "uses DTE-specific IV proxies when configured" do
      vix_only_builder = described_class.new(
        spx_series: spx_series,
        vix_series: vix_series,
        vix9d_series: vix9d_series,
        vix1d_series: vix1d_series,
        iv_map: { "0DTE" => "VIX1D", "9DTE" => "VIX9D", "30DTE" => "VIX" }
      )

      zero_dte_chain = vix_only_builder.build(
        target_time: target_time,
        expiration_date: Date.new(2026, 4, 9),
        symbol: "SPXW"
      )
      longer_dte_chain = vix_only_builder.build(
        target_time: target_time,
        expiration_date: Date.new(2026, 4, 20),
        symbol: "SPXW"
      )

      zero_dte_atm = zero_dte_chain.call_opts.min_by { |option| (option.strike - zero_dte_chain.underlying_price).abs }
      longer_dte_atm = longer_dte_chain.call_opts.min_by { |option| (option.strike - longer_dte_chain.underlying_price).abs }

      expect(zero_dte_atm.volatility).to be < longer_dte_atm.volatility
    end

    it "raises an informative error when required series are not aligned" do
      misaligned_vix = series(candle("2026-04-09T16:59:00Z", open: 18.1, high: 18.5, low: 17.9, close: 18.3))
      misaligned_builder = described_class.new(
        spx_series: spx_series,
        vix_series: misaligned_vix
      )

      expect do
        misaligned_builder.build(target_time: target_time, expiration_date: expiration_date, symbol: "SPXW")
      end.to raise_error(ArgumentError, /not aligned/)
    end
  end
end
