module OptionsTrader
  module Indicators
    class VIXVolatility
      # Calculate volatility estimate using VIX close prices for SPX options
      # @param spot_price [Float] Current SPX price
      # @param strike_price [Float] Option strike price
      # @param time_to_expiry [Float] Time to expiration in years
      # @param vix [Float] Current VIX close price (as percentage, e.g., 20.5)
      # @param vix9d [Float] Current VIX9D close price (as percentage, e.g., 22.1)
      # @param option_type [String] "CALL" or "PUT"
      # @param current_timestamp [Time] Current timestamp (default: now)
      # @param recent_vix_history [Array] Recent VIX close prices for momentum analysis (optional)
      # @return [Float] Volatility estimate (as decimal, e.g., 0.205 for 20.5%)
      def self.calculate(
        spot_price:,
        strike_price:,
        dte:,
        vix:,
        vix9d:,
        current_timestamp:,
        option_type: OptionsTrader::CALL,
        recent_vix_history: []
      )
        # Convert VIX percentages to decimals
        vix_decimal = vix / 100.0
        vix9d_decimal = vix9d / 100.0

        # Step 1: Interpolate volatility for exact DTE using VIX term structure
        base_volatility = interpolate_vix_term_structure(vix9d_decimal, vix_decimal, dte)

        # Step 2: Apply SPX volatility skew (puts more expensive than calls)
        skew_adjusted_vol = apply_spx_skew(
          base_volatility, spot_price, strike_price, dte, option_type
        )

        # Step 3: Apply short-term momentum and regime adjustments
        momentum_adjusted_vol = apply_vix_momentum_effects(
          skew_adjusted_vol, vix, vix9d, recent_vix_history, dte
        )

        # Step 4: Apply intraday timing effects for very short DTE
        final_volatility = apply_timing_effects(
          momentum_adjusted_vol, current_timestamp, dte, vix, vix9d
        )

        # base_volatility
        # skew_adjusted_vol
        # momentum_adjusted_vol
        final_volatility
      end

      private

      # Interpolate volatility between VIX9D and VIX based on DTE
      def self.interpolate_vix_term_structure(vix9d, vix30d, dte)
        case dte
        when 0..9
          # Linear interpolation from VIX9D to VIX30D
          # For very short DTE, bias toward VIX9D with slight premium
          weight = dte / 9.0
          base_vol = vix9d + weight * (vix30d - vix9d)

          # Add short-term premium for very short DTE
          short_term_premium = dte <= 2 ? 1.05 : 1.0
          base_vol * short_term_premium

        when 10..30
          # Linear interpolation between 9-day and 30-day
          weight = (dte - 9) / 21.0
          vix9d + weight * (vix30d - vix9d)

        when 31..60
          # Extrapolate beyond 30 days with slight decay (mean reversion)
          decay_factor = [30.0 / dte * 0.98, 0.90].max
          vix30d * decay_factor

        else
          # Longer-term extrapolation with more decay
          decay_factor = [30.0 / dte * 0.95, 0.85].max
          vix30d * decay_factor
        end
      end

      # Apply SPX-specific volatility skew
      def self.apply_spx_skew(base_vol, spot_price, strike_price, dte, option_type)
        moneyness = strike_price / spot_price
        # Aggressive adjustments for extreme OTM options to match actual pricing
        # SPX has pronounced negative skew (higher vol for OTM puts)
        base_skew_multiplier = case moneyness
                              when 0.80..0.90  # Deep OTM puts
                                1.35 + (0.90 - moneyness) * 1.5
                              when 0.90..0.95  # OTM puts
                                1.15 + (0.95 - moneyness) * 4.0
                              when 0.95..1.05  # ATM region
                                1.0 + (1.0 - moneyness).abs * 0.8
                              when 1.05..1.15  # OTM calls
                                0.88 - (moneyness - 1.05) * 2.5
                              when 1.15..1.25  # Deep OTM calls
                                0.75 - (moneyness - 1.15) * 1.5
                              else
                                moneyness < 0.80 ? 1.50 : 0.70
                              end

        # Adjust skew based on option type (puts get full skew, calls get inverse)
        skew_multiplier = case option_type
                         when OptionsTrader::PUT
                           base_skew_multiplier
                         when OptionsTrader::CALL
                           # Calls have inverse relationship - lower vol for OTM calls
                           if moneyness > 1.05
                             base_skew_multiplier
                           else
                             # ATM and ITM calls get normal pricing
                             [base_skew_multiplier, 1.1].min
                           end
                         else
                           base_skew_multiplier
                         end

        # Enhanced skew effects for shorter DTE (opposite of before - more dramatic)
        dte_adjustment = case dte
                        when 0..2   then 1.0     # Full skew effect for 0-2 DTE
                        when 3..7   then 0.9     # Slight reduction for 3-7 DTE
                        when 8..30  then 0.8     # Moderate reduction for 8-30 DTE
                        else             0.7     # Lower skew for longer-term
                        end

        final_skew = 1.0 + (skew_multiplier - 1.0) * dte_adjustment
        base_vol * final_skew
      end

      # Apply VIX momentum and term structure effects
      def self.apply_vix_momentum_effects(base_vol, vix, vix9d, recent_vix_history, dte)
        # VIX term structure analysis
        vix_spread = vix - vix9d

        # Term structure regime adjustments
        ts_adjustment = case vix_spread
                       when 3.0..Float::INFINITY  # Strong contango (normal market)
                         0.97   # Short-term vol relatively low
                       when 1.0..3.0             # Normal contango
                         1.0    # Normal structure
                       when 0.0..1.0             # Flat structure
                         1.02   # Slight short-term premium
                       when -2.0..0.0            # Backwardation (stress)
                         1.08   # Short-term stress premium
                       else                       # Strong backwardation (panic)
                         1.15   # High short-term stress
                       end

        # VIX momentum from recent history
        momentum_adjustment = 1.0
        if recent_vix_history.length >= 10
          recent_avg = recent_vix_history.sum / recent_vix_history.length.to_f
          momentum_change = (vix - recent_avg) / recent_avg

          momentum_adjustment = case momentum_change
                               when 0.15..Float::INFINITY  # VIX spiking >15%
                                 1.12
                               when 0.10..0.15            # VIX up 10-15%
                                 1.08
                               when 0.05..0.10            # VIX up 5-10%
                                 1.04
                               when -0.05..0.05           # VIX stable
                                 1.0
                               when -0.10..-0.05          # VIX down 5-10%
                                 0.98
                               when -0.15..-0.10          # VIX down 10-15%
                                 0.96
                               else                        # VIX collapsing >15%
                                 0.94
                               end
        end

        # Volatility level regime adjustments
        vol_level_adjustment = case vix
                              when 0..12   then 0.95  # Very low vol regime
                              when 12..18  then 0.98  # Low vol regime
                              when 18..25  then 1.0   # Normal vol regime
                              when 25..35  then 1.05  # High vol regime
                              when 35..50  then 1.08  # Very high vol regime
                              else              1.12  # Extreme vol regime
                              end

        # Weight adjustments based on DTE (stronger effects for shorter DTE)
        dte_weight = case dte
                    when 0..3   then 1.0     # Full weight for very short-term
                    when 4..7   then 0.8     # Reduced weight for weekly
                    when 8..30  then 0.6     # Further reduced for monthly
                    else             0.4     # Minimal weight for longer-term
                    end

        # Combine all adjustments
        combined_effect = (
          ts_adjustment * momentum_adjustment * vol_level_adjustment - 1.0
        ) * dte_weight + 1.0

        base_vol * combined_effect
      end

      # Apply intraday timing effects for short-term options
      def self.apply_timing_effects(base_vol, timestamp, dte, vix, vix9d)
        return base_vol if dte > 7  # Only apply to short-term options

        hour = timestamp.hour
        minute = timestamp.minute
        wday = timestamp.wday

        timing_multiplier = 1.0

        # Reduced intraday volatility patterns
        case hour
        when 9  # Market open hour
          if minute < 30
            timing_multiplier *= 1.0      # Pre-market, stable
          elsif minute < 45
            timing_multiplier *= dte <= 1 ? 1.15 : 1.08  # Reduced opening bell volatility
          else
            timing_multiplier *= dte <= 1 ? 1.10 : 1.04  # Reduced post-open momentum
          end

        when 10..11  # Morning session
          timing_multiplier *= dte <= 1 ? 1.04 : 1.01

        when 12..13  # Lunch period
          timing_multiplier *= 0.97  # Less dramatic lunch reduction

        when 14  # Afternoon session (common announcement time)
          if [0, 15, 30].include?(minute)  # :00, :15, :30 (FOMC, economic data)
            timing_multiplier *= 1.08  # Reduced news premium
          else
            timing_multiplier *= 1.01
          end

        when 15  # Market close hour
          if minute >= 50
            timing_multiplier *= dte <= 1 ? 1.12 : 1.06  # Reduced final 10 minutes
          elsif minute >= 30
            timing_multiplier *= dte <= 1 ? 1.08 : 1.04  # Reduced closing hour volatility
          else
            timing_multiplier *= 1.02
          end
        end

        # Reduced day of week effects for very short DTE
        if dte <= 1
          case wday
          when 1  # Monday - weekend gap risk
            timing_multiplier *= 1.03  # Reduced weekend gap premium
          when 5  # Friday - weekend time decay acceleration
            timing_multiplier *= 1.04  # Reduced weekend premium
          end
        end

        # Reduced high volatility environment amplification
        if vix > 30
          timing_multiplier *= dte <= 1 ? 1.04 : 1.02  # Reduced high vol premium
        end

        # Reduced short-term volatility spike amplification
        if vix9d > vix * 1.05 && dte <= 3
          timing_multiplier *= 1.03  # Reduced spike premium
        end

        # Reduced expiration day effects (0 DTE)
        if dte == 0
          case hour
          when 9..11   then timing_multiplier *= 1.06  # Reduced morning expiration volatility
          when 12..14  then timing_multiplier *= 1.12  # Reduced midday gamma effects
          when 15      then timing_multiplier *= 1.20  # Reduced final hour gamma explosion
          end
        end

        base_vol * timing_multiplier
      end
    end
  end
end