require "pry"
require "json"
require_relative "schwab/schwab"
require_relative "schwab/data_objects/quote"

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

  def initialize(cache: false)
    @cache = cache
  end

  def check
    if quote.mark <= VIXThresholds::LOW
      VIXStatusNames::LOW
    elsif quote.mark >= VIXThresholds::HIGH
      VIXStatusNames::HIGH
    else
      VIXStatusNames::NORMAL
    end
  end

  def reset
    @quote = nil
  end

  def quote
    # REVIEW: the schwab mixin should return the data objects
    if cache
      @quote ||= Schwab.quote("$VIX")
    else
      Schwab.quote("$VIX")
    end
  end
end
