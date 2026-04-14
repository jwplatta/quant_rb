# frozen_string_literal: true

class SpySmaCrossover < QuantRb::Strategy
  SHARE_QUANTITY = 100
  FAST_PERIOD = 10
  SLOW_PERIOD = 30

  attr_reader :spy

  def initialize
    set_start_date(2024, 1, 1)
    set_end_date(2024, 12, 31)
    set_cash(100_000)
    @spy = add_equity("SPY", resolution: :minute)
    @previous_signal = nil
  end

  def on_data(slice)
    return unless slice.bars[@spy]

    candles = securities[@spy].candles
    return if candles.size < SLOW_PERIOD

    fast_sma = average_close(candles.last(FAST_PERIOD))
    slow_sma = average_close(candles.last(SLOW_PERIOD))
    signal = fast_sma <=> slow_sma

    if should_enter_long?(signal)
      market_order(@spy, SHARE_QUANTITY)
    elsif should_exit_long?(signal)
      market_order(@spy, -SHARE_QUANTITY)
    end

    @previous_signal = signal
  end

  private

  def average_close(candles)
    candles.sum(&:close) / candles.size.to_f
  end

  def should_enter_long?(signal)
    @previous_signal && @previous_signal <= 0 && signal == 1 && !portfolio.invested?
  end

  def should_exit_long?(signal)
    @previous_signal && @previous_signal >= 0 && signal == -1 && portfolio.invested?
  end
end
