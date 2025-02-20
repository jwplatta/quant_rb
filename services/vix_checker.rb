require "pry"
require "json"
require_relative "schwab"
require_relative "../data_objects/quote"

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
    @client = Schwab.client
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
    if cache
      @quote ||= @client.get_quote("$VIX").then do |resp|
        JSON.parse(resp.body, symbolize_names: true).then do |data|
          DataObjects::QuoteFactory.build(data)
        end
      end
    else
      @client.get_quote("$VIX").then do |resp|
        JSON.parse(resp.body, symbolize_names: true).then do |data|
          DataObjects::QuoteFactory.build(data)
        end
      end
    end
  end
end
