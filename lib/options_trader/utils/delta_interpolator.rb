module OptionsTrader
  module Utils
    class DeltaInterpolator
      def self.interpolate(strike_deltas, target_strike)
        # strike_deltas is a hash: { strike => delta }
        sorted_strikes = strike_deltas.keys.sort

        # Handle boundaries
        return strike_deltas[sorted_strikes.first] if target_strike <= sorted_strikes.first
        return strike_deltas[sorted_strikes.last] if target_strike >= sorted_strikes.last
        # Find bracketing strikes
        sorted_strikes.each_cons(2) do |lower_strike, upper_strike|
          if lower_strike <= target_strike && target_strike <= upper_strike
            lower_delta = strike_deltas[lower_strike]
            upper_delta = strike_deltas[upper_strike]

            weight = (target_strike - lower_strike).to_f / (upper_strike - lower_strike)
            return lower_delta + weight * (upper_delta - lower_delta)
          end
        end
      end
    end
  end
end
