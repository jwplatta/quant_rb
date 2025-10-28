module OptionsTrader
  module SyntheticData
    module Transform
      class StrikeAdder
        DEFAULT_MIN_OFFSET = -3000
        DEFAULT_MAX_OFFSET = 1000
        DEFAULT_INNER_OFFSET = 225
        DEFAULT_INNER_STEP = 5
        DEFAULT_OUTER_STEP = 25
        DEFAULT_MIN_MARK = 0.025

        # Adds synthetic options for missing strikes in the option chain
        # Returns a hash with :calls and :puts arrays
        #
        # @param calls [Array<DataObjects::Option>] Array of call options
        # @param puts [Array<DataObjects::Option>] Array of put options
        # @param features [Hash] Feature values to propagate to synthetic options (e.g., vix9d, vvix, skew)
        # @param min_strike [Float, nil] Minimum strike price (optional)
        # @param max_strike [Float, nil] Maximum strike price (optional)
        # @param min_offset [Integer] Offset below underlying for min strike (default: -3000)
        # @param max_offset [Integer] Offset above underlying for max strike (default: 1000)
        # @param inner_offset [Integer] ATM range for dense strikes (default: 225)
        # @param inner_step [Integer] Strike spacing within ATM range (default: 5)
        # @param outer_step [Integer] Strike spacing outside ATM range (default: 25)
        # @return [Hash] { calls: Array, put_opts: Array }
        def self.add_strikes(
          calls:,
          put_opts:,
          features: {},
          min_strike: nil,
          max_strike: nil,
          min_offset: DEFAULT_MIN_OFFSET,
          max_offset: DEFAULT_MAX_OFFSET,
          inner_offset: DEFAULT_INNER_OFFSET,
          inner_step: DEFAULT_INNER_STEP,
          outer_step: DEFAULT_OUTER_STEP
        )
          new(
            min_offset: min_offset,
            max_offset: max_offset,
            inner_offset: inner_offset,
            inner_step: inner_step,
            outer_step: outer_step
          ).add_strikes(
            calls: calls,
            put_opts: put_opts,
            features: features,
            min_strike: min_strike,
            max_strike: max_strike
          )
        end

        def initialize(
          min_offset: DEFAULT_MIN_OFFSET,
          max_offset: DEFAULT_MAX_OFFSET,
          inner_offset: DEFAULT_INNER_OFFSET,
          inner_step: DEFAULT_INNER_STEP,
          outer_step: DEFAULT_OUTER_STEP
        )
          @min_offset = min_offset
          @max_offset = max_offset
          @inner_offset = inner_offset
          @inner_step = inner_step
          @outer_step = outer_step
        end

        def add_strikes(calls:, put_opts:, features: {}, min_strike: nil, max_strike: nil)
          raise ArgumentError, 'At least 1 call and 1 put options are required' unless calls.size > 0 && put_opts.size > 0

          underlying_price = calls.first.underlying_price || put_opts.first.underlying_price
          dte = calls.first.days_to_expiration || put_opts.first.days_to_expiration
          expiration_date = calls.first.expiration_date || put_opts.first.expiration_date
          underlying_symbol = calls.first.underlying_symbol || put_opts.first.underlying_symbol

          # Generate target strikes
          target_strikes = generate_target_strikes(
            underlying_price,
            min_strike: min_strike,
            max_strike: max_strike
          )

          # Build complete option arrays with synthetic options
          complete_calls, complete_puts = build_complete_option_arrays(
            underlying_symbol: underlying_symbol,
            calls: calls,
            put_opts: put_opts,
            target_strikes: target_strikes,
            underlying_price: underlying_price,
            dte: dte,
            expiration_date: expiration_date,
            feature_values: features
          )

          { calls: complete_calls, put_opts: complete_puts }
        end

        private

        # Generates strike prices with dense spacing near ATM and wider spacing OTM
        # Inner strikes use 5-point increments, outer strikes use 25-point increments
        def generate_target_strikes(
          underlying_price,
          min_strike: nil,
          max_strike: nil
        )
          # Round underlying to nearest outer_step
          base_strike = (underlying_price / @outer_step.to_f).round * @outer_step

          unless min_strike.present? && max_strike.present?
            min_strike = base_strike + @min_offset
            max_strike = base_strike + @max_offset
          end

          inner_min_strike = base_strike - @inner_offset
          inner_max_strike = base_strike + @inner_offset

          # Align inner_max_strike to outer_step boundary
          while inner_max_strike % @outer_step != 0
            inner_max_strike += @inner_step
          end

          strikes = []
          current_strike = min_strike

          while current_strike <= max_strike
            strikes << current_strike
            step = (current_strike >= inner_min_strike && current_strike < inner_max_strike) ? @inner_step : @outer_step
            current_strike += step
          end

          strikes.sort
        end

        # Merges existing options with synthetic options for missing strikes
        # Synthetic options carry the same feature values as real options
        def build_complete_option_arrays(
          underlying_symbol:,
          calls:,
          put_opts:,
          target_strikes:,
          underlying_price:,
          dte:,
          expiration_date:,
          feature_values: nil
        )
          min_strike = target_strikes.min
          max_strike = target_strikes.max
          calls_by_strike = calls.index_by(&:strike)
          puts_by_strike = put_opts.index_by(&:strike)

          complete_calls = []
          complete_puts = []

          target_strikes.each do |strike|
            if calls_by_strike[strike]
              complete_calls << calls_by_strike[strike]
            else
              complete_calls << create_synthetic_option(
                underlying_symbol: underlying_symbol,
                strike: strike,
                contract_type: 'CALL',
                underlying_price: underlying_price,
                days_to_expiration: dte,
                expiration_date: expiration_date,
                mark: (strike == max_strike ? DEFAULT_MIN_MARK : nil),
                feature_values: feature_values
              )
            end

            if puts_by_strike[strike]
              complete_puts << puts_by_strike[strike]
            else
              complete_puts << create_synthetic_option(
                underlying_symbol: underlying_symbol,
                strike: strike,
                contract_type: 'PUT',
                underlying_price: underlying_price,
                days_to_expiration: dte,
                expiration_date: expiration_date,
                mark: (strike == min_strike ? DEFAULT_MIN_MARK : nil),
                feature_values: feature_values
              )
            end
          end

          [complete_calls, complete_puts]
        end

        # Creates a synthetic option for a missing strike
        # Features are copied from real options to ensure consistent market context
        def create_synthetic_option(
          underlying_symbol:,
          strike:,
          contract_type:,
          underlying_price:,
          days_to_expiration:,
          expiration_date:,
          mark: nil,
          feature_values: nil
        )
          option = DataObjects::Option.new(
            symbol: create_option_symbol(underlying_symbol, strike, contract_type, expiration_date),
            underlying_symbol: underlying_symbol,
            strike: strike,
            put_call: contract_type,
            mark: mark,
            underlying_price: underlying_price,
            expiration_date: expiration_date,
            days_to_expiration: days_to_expiration,
            delta: nil,
            open_interest: 0,
            total_volume: 1,
            timestamp: nil
          )

          if feature_values
            feature_values.each do |key, value|
              option.set_feature(key, value)
            end
          end

          option
        end

        # Creates OCC-formatted option symbol
        def create_option_symbol(underlying_symbol, strike, contract_type, expiration_date)
          normalized = underlying_symbol.to_s.sub(/\A[\^\$]/, '')
          exp_str = expiration_date.to_s.tr('-', '')
          contract_letter = contract_type[0]
          strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
          "#{normalized}#{exp_str}#{contract_letter}#{strike_str}"
        end
      end
    end
  end
end
