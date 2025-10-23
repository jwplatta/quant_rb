module OptionsTrader
  module Services
    # Generates historical option chains for a specific point in time using LOCF (Last Observation Carried Forward).
    # Creates synthetic options for missing strikes and enriches chains with market features (VIX, skew, etc.).
    class HistoricalSnapshot
      DEFAULT_MIN_MARK = 0.025
      DEFAULT_STALENESS_THRESHOLD_MINUTES = 5

      # Strike generation defaults
      DEFAULT_MIN_OFFSET = -3000
      DEFAULT_MAX_OFFSET = 1000
      DEFAULT_INNER_OFFSET = 225
      DEFAULT_INNER_STEP = 5
      DEFAULT_OUTER_STEP = 25

      # @param symbol [String] Underlying symbol (e.g., 'SPXW')
      # @param valid_time [Time] Point in time for the historical snapshot
      def initialize(valid_time:)
        @valid_time = valid_time
      end

      def get_quote(symbol, **kwargs)
        strike_price = kwargs[:strike_price]
        generate_quote(strike_price)
      end

      # Retrieves a complete option chain with synthetic options for missing strikes.
      # Optionally enriches with market features like VIX, skew, etc.
      #
      # @param symbol [String] Underlying symbol
      # @param expiration_date [Date] Option expiration date
      # @param window [Integer] Staleness threshold in minutes for LOCF
      # @param min_strike [Integer] Minimum strike price
      # @param max_strike [Integer] Maximum strike price
      # @param features [Hash] Market features to include (e.g., {vix9d: true, vvix: true, skew: true})
      # @return [DataObjects::OptionsChain] Complete option chain with calls and puts
      def get_option_chain(symbol, **kwargs)
        expiration_date = kwargs[:expiration_date]
        raise ArgumentError, "expiration_date is required" if expiration_date.nil?

        window = kwargs.fetch(:window, DEFAULT_STALENESS_THRESHOLD_MINUTES)

        min_strike = kwargs[:min_strike]
        max_strike = kwargs[:max_strike]
        features = kwargs[:features] || {}

        generate_options_chain(symbol, expiration_date, window, min_strike, max_strike, features)
      end

      private

      # Core method that fetches historical data, generates synthetic options, interpolates prices,
      # and enforces monotonicity to create a complete, arbitrage-free option chain.
      def generate_options_chain(underlying_symbol, expiration_date, window, min_strike = nil, max_strike = nil, features = {})
        # Step 1: Fetch existing options using LOCF
        # If features are requested, use the enriched query; otherwise use the basic query

        if features.any?
          # Fetch CALLs and PUTs separately with enriched features
          call_records = Queries::OptionChainWithFeatures.fetch(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            end_time: @valid_time,
            window_minutes: window,
            contract_type: 'CALL',
            features: features,
            max_moneyness: 1.01
          )

          put_records = Queries::OptionChainWithFeatures.fetch(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            end_time: @valid_time,
            window_minutes: window,
            contract_type: 'PUT',
            features: features,
            max_moneyness: 1.01
          )
          records = call_records + put_records
        else
          records = OptionChainHistory.fetch_with_locf(
            expiration_date: expiration_date,
            underlying_symbol: underlying_symbol,
            end_time: @valid_time,
            window_minutes: window
          )
        end

        raise "No option data found for #{underlying_symbol} expiring on #{expiration_date} at #{@valid_time}" if records.empty?

        # Step 2: Convert to arrays and extract underlying price
        call_opts, put_opts, underlying_price, dte = partition_records(records)

        # Step 2.5: Extract feature values from first record (all records have same feature values)
        feature_values = extract_feature_values(records.first) if features.any?

        # Step 3: Generate target strikes if not provided
        target_strikes = generate_target_strikes(
          underlying_price, min_strike: min_strike, max_strike: max_strike
        )

        # Step 4: Build complete option arrays with synthetic options
        complete_calls, complete_puts = build_complete_option_arrays(
          underlying_symbol, call_opts, put_opts, target_strikes, underlying_price, dte, expiration_date, feature_values
        )

        # Step 5: Interpolate missing prices and enforce monotonicity
        complete_calls = Utils::OptionPriceInterpolator.interpolate(complete_calls, contract_type: 'CALL').then do |opts|
          binding.pry
          Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'CALL')
        end
        complete_puts = Utils::OptionPriceInterpolator.interpolate(complete_puts, contract_type: 'PUT').then do |opts|
          Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'PUT')
        end

        DataObjects::OptionsChain.new(
          symbol: underlying_symbol,
          underlying_price: underlying_price,
          call_opts: complete_calls,
          put_opts: complete_puts
        )
      end

      def partition_records(records)
        underlying_price = records.first&.dig('underlying_price')&.to_f
        dte = records.first&.dig('dte')&.to_i

        options = records.map { |record| build_option_from_record(record) }

        call_opts, put_opts = options.partition { |option| option.put_call == 'CALL' }

        [call_opts, put_opts, underlying_price, dte]
      end

      # Extracts market feature values (VIX, skew, etc.) from a database record
      # by filtering out standard option fields.
      def extract_feature_values(record)
        return {} if record.nil?

        feature_hash = {}
        record.each do |key, value|
          # Skip standard option fields
          next if %w[symbol strike contract_type expiration_date mark volume open_price
                     close_price high_price low_price valid_time dte underlying_price moneyness].include?(key)
          # Collect feature values (vix9d, vvix, skew, etc.)
          feature_hash[key] = value&.to_f if value
        end
        feature_hash
      end

      def build_option_from_record(record)
        # Handle both enriched records (with 'dte') and basic records (calculate from dates)
        days_to_expiration = if record['dte']
                               record['dte'].to_i
                             else
                               (Date.parse(record['expiration_date']) - record['valid_time'].to_date).to_i
                             end

        option = DataObjects::Option.new(
          symbol: record['symbol'],
          underlying_symbol: record['underlying_symbol'],
          strike: record['strike'].to_i,
          put_call: record['contract_type'],
          mark: record['mark'].to_f,
          underlying_price: record['underlying_price'].to_f,
          expiration_date: record['expiration_date'],
          days_to_expiration: days_to_expiration,
          delta: nil,
          open_interest: 0,
          total_volume: record.fetch('volume', 0).to_i,
          open: record.fetch('open_price', 0).to_f,
          close: record.fetch('close_price', 0).to_f,
          high: record.fetch('high_price', 0).to_f,
          low: record.fetch('low_price', 0).to_f,
          timestamp: record['valid_time']
        )

        # Store enriched features as dynamic attributes on the option object
        # Features like vix9d, vvix, skew, moneyness will be accessible via opt.vix9d, etc.
        record.each do |key, value|
          # Skip standard option fields
          next if %w[symbol strike contract_type expiration_date mark volume open_price
                     close_price high_price low_price valid_time dte underlying_price moneyness].include?(key)
          # Set dynamic features (vix9d, vvix, skew, moneyness, etc.)
          option.set_feature(key, value&.to_f) if value
        end

        option
      end

      # Generates strike prices with dense spacing near ATM and wider spacing OTM.
      # Inner strikes use 5-point increments, outer strikes use 25-point increments.
      def generate_target_strikes(
        underlying_price,
        min_strike: nil,
        max_strike: nil,
        min_offset: DEFAULT_MIN_OFFSET,
        max_offset: DEFAULT_MAX_OFFSET,
        inner_offset: DEFAULT_INNER_OFFSET,
        inner_step: DEFAULT_INNER_STEP,
        outer_step: DEFAULT_OUTER_STEP
      )
        # Round underlying to nearest outer_step
        base_strike = (underlying_price / outer_step.to_f).round * outer_step

        unless min_strike.present? && max_strike.present?
          min_strike = base_strike + min_offset
          max_strike = base_strike + max_offset
        end

        inner_min_strike = base_strike - inner_offset
        inner_max_strike = base_strike + inner_offset

        # Align inner_max_strike to outer_step boundary
        while inner_max_strike % outer_step != 0
          inner_max_strike += inner_step
        end

        strikes = []
        current_strike = min_strike

        while current_strike <= max_strike
          strikes << current_strike
          step = (current_strike >= inner_min_strike && current_strike < inner_max_strike) ? inner_step : outer_step
          current_strike += step
        end

        strikes.sort
      end

      # Merges existing options with synthetic options for missing strikes.
      # Synthetic options carry the same feature values as real options.
      def build_complete_option_arrays(
        underlying_symbol, calls, puts,
        target_strikes, underlying_price, dte, expiration_date, feature_values = nil
      )
        min_strike = target_strikes.min
        max_strike = target_strikes.max
        calls_by_strike = calls.index_by(&:strike)
        puts_by_strike = puts.index_by(&:strike)

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

      # Creates a synthetic option for a missing strike. Features are copied from real options
      # to ensure consistent market context across the entire chain.
      def create_synthetic_option(underlying_symbol:,strike:, contract_type:, underlying_price:, days_to_expiration:, expiration_date:, mark: nil, feature_values: nil)
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
          timestamp: @datetime
        )

        if feature_values
          feature_values.each do |key, value|
            option.set_feature(key, value)
          end
        end

        option
      end

      def create_option_symbol(underlying_symbol, strike, contract_type, expiration_date)
        normalized = underlying_symbol.to_s.sub(/\A[\^\$]/, '')
        exp_str = expiration_date.to_s.tr('-', '')
        contract_letter = contract_type[0]
        strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
        "#{normalized}#{exp_str}#{contract_letter}#{strike_str}"
      end

      def generate_quote(strike_price)
        # TODO: Implement quote generation if needed
        raise NotImplementedError, "get_quote not yet implemented for HistoricalSnapshot"
      end
    end
  end
end
