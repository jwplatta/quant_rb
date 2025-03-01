require "pry"
require "json"
require_relative "schwab/schwab"

class VIXChecker
  include Schwab

  attr_reader :cache

  module VIXThresholds
    LOW=12.0
    HIGH=20.0
  end

  module VIXStatusNames
    LOW="low"
    HIGH="high"
    NORMAL="normal"
  end

  VIX_SYMBOL = "$VIX"

  def initialize(cache: false)
    @cache = cache
  end

  def check
    if vix_quote.mark <= VIXThresholds::LOW
      VIXStatusNames::LOW
    elsif vix_quote.mark >= VIXThresholds::HIGH
      VIXStatusNames::HIGH
    else
      VIXStatusNames::NORMAL
    end
  end

  def reset
    @vix_quote = nil
  end

  def vix_quote
    # REVIEW: the schwab mixin should return the data objects
    if cache
      @vix_quote ||= quote(VIX_SYMBOL)
    else
      quote(VIX_SYMBOL)
    end
  end
end
