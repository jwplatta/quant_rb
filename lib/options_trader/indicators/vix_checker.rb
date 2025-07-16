# frozen_string_literal: true

require 'pry'
require 'json'

module OptionsTrader
  module Indicators
    class VIXChecker
      include OptionsTrader::Schwab

      module VIXThresholds
        LOW = 12.0
        HIGH = 20.0
      end

      module VIXStatusNames
        LOW = 'low'
        HIGH = 'high'
        NORMAL = 'normal'
      end

      VIX_SYMBOL = '$VIX'

      def check
        if vix_quote.mark <= VIXThresholds::LOW
          VIXStatusNames::LOW
        elsif vix_quote.mark >= VIXThresholds::HIGH
          VIXStatusNames::HIGH
        else
          VIXStatusNames::NORMAL
        end
      end

      def refresh
        @vix_quote = nil
      end

      def vix_quote
        @vix_quote ||= quote(VIX_SYMBOL)
      end
    end
  end
end
