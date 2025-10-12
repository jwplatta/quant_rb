module OptionsTrader
  module Indicators
    class CoxRossRubinstein
      # Cox-Ross-Rubinstein binomial option pricing model
      # @param spot_price [Float] Current price of underlying asset (S0)
      # @param strike_price [Float] Option strike price (K)
      # @param time_to_expiry [Float] Time to expiration in years (T)
      # @param risk_free_rate [Float] Risk-free interest rate (r)
      # @param volatility [Float] Volatility (sigma)
      # @param option_type [String] "CALL" or "PUT"
      # @param timesteps [Integer] Number of time steps (n), defaults to daily steps
      # @param dividend_yield [Float] Annualized dividend yield (default 0)
      # @return [Float] Option price
      def self.calculate(
        spot_price:,
        strike_price:,
        time_to_expiry:,
        risk_free_rate:,
        volatility:,
        option_type: OptionsTrader::CALL,
        dividend_yield: 0.0
      )
        # Use daily timetimesteps by default (252 trading days per year)
        timesteps ||= [1, (time_to_expiry * 365).round].max
        # Calculate CRR parameters
        dt = time_to_expiry / timesteps.to_f
        u = Math.exp(volatility * Math.sqrt(dt))
        d = 1.0 / u
        p = (Math.exp((risk_free_rate - dividend_yield) * dt) - d) / (u - d)
        discount = Math.exp(-risk_free_rate * dt)

        # Initialize asset price tree
        s = Array.new(timesteps + 1) { Array.new(timesteps + 1) }

        # Build forward asset price tree
        (0..timesteps).each do |i|
          (0..i).each do |j|
            s[i][j] = spot_price * (u ** j) * (d ** (i - j))
          end
        end

        # Initialize option value array
        v = Array.new(timesteps + 1) { Array.new(timesteps + 1) }

        # Calculate terminal option values (at expiration)
        (0..timesteps).each do |j|
          case option_type
          when OptionsTrader::CALL
            v[timesteps][j] = [0, s[timesteps][j] - strike_price].max
          when OptionsTrader::PUT
            v[timesteps][j] = [0, strike_price - s[timesteps][j]].max
          else
            raise ArgumentError, "option_type must be CALL or PUT"
          end
        end

        # Backward induction to find option price
        (timesteps - 1).downto(0) do |i|
          (0..i).each do |j|
            expected_value = p * v[i + 1][j + 1] + (1.0 - p) * v[i + 1][j]
            v[i][j] = discount * expected_value

            # For American options, check early exercise (commented out for European)
            # if american_option
            #   case option_type
            #   when OptionsTrader::CALL
            #     intrinsic_value = [0, s[i][j] - strike_price].max
            #   when OptionsTrader::PUT
            #     intrinsic_value = [0, strike_price - s[i][j]].max
            #   end
            #   v[i][j] = [v[i][j], intrinsic_value].max
            # end
          end
        end

        v[0][0]
      end
    end
  end
end
