module OptionsTrader
  module Services
    class HistoricalSnapshot
      DEFAULT_MIN_MARK = 0.025
      DEFAULT_STALENESS_THRESHOLD_MINUTES = 5

      # Strike generation defaults
      DEFAULT_MIN_OFFSET = -3000
      DEFAULT_MAX_OFFSET = 1000
      DEFAULT_INNER_OFFSET = 225
      DEFAULT_INNER_STEP = 5
      DEFAULT_OUTER_STEP = 25

      def initialize(symbol:, valid_time:)
        @symbol = symbol
        @valid_time = valid_time
      end

      def get_quote(symbol, **kwargs)
        strike_price = kwargs[:strike_price]
        generate_quote(strike_price)
      end

      def get_option_chain(symbol, **kwargs)
        expiration_date = kwargs[:expiration_date]
        raise ArgumentError, "expiration_date is required" if expiration_date.nil?

        window = kwargs.fetch(:window, DEFAULT_STALENESS_THRESHOLD_MINUTES)

        min_strike = kwargs[:min_strike]
        max_strike = kwargs[:max_strike]

        generate_options_chain(expiration_date, window, min_strike, max_strike)
      end

      private

      def generate_options_chain(expiration_date, window, min_strike = nil, max_strike = nil)
        # Step 1: Fetch existing options using LOCF

        records = OptionChainHistory.fetch_with_locf(
          expiration_date: expiration_date,
          underlying_symbol: @symbol,
          end_time: @valid_time,
          window_minutes: window
        )

        # Step 2: Convert to arrays and extract underlying price
        call_opts, put_opts, underlying_price = partition_records(records)

        # Step 3: Generate target strikes if not provided
        target_strikes = generate_target_strikes(
          underlying_price, min_strike: min_strike, max_strike: max_strike
        )

        # Step 4: Build complete option arrays with synthetic options
        complete_calls, complete_puts = build_complete_option_arrays(
          call_opts, put_opts, target_strikes, underlying_price, expiration_date
        )

        # Step 5: Interpolate missing prices and enforce monotonicity
        complete_calls = Utils::OptionPriceInterpolator.interpolate(complete_calls, contract_type: 'CALL').then do |opts|
          Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'CALL')
        end
        complete_puts = Utils::OptionPriceInterpolator.interpolate(complete_puts, contract_type: 'PUT').then do |opts|
          Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'PUT')
        end

        DataObjects::OptionsChain.new(
          symbol: @symbol,
          underlying_price: underlying_price,
          call_opts: complete_calls,
          put_opts: complete_puts
        )
      end

      def partition_records(records)
        underlying_price = records.first&.dig('underlying_price')&.to_f

        options = records.map { |record| build_option_from_record(record) }
        calls, puts = options.partition { |option| option.put_call == 'CALL' }

        [calls, puts, underlying_price]
      end

      def build_option_from_record(record)
        days_to_expiration = (Date.parse(record['expiration_date']) - record['valid_time'].to_date).to_i

        DataObjects::Option.new(
          symbol: record['symbol'],
          underlying_symbol: @symbol,
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
      end

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

      def build_complete_option_arrays(calls, puts, target_strikes, underlying_price, expiration_date)
        min_strike = target_strikes.min
        max_strike = target_strikes.max
        calls_by_strike = calls.index_by(&:strike)
        puts_by_strike = puts.index_by(&:strike)

        complete_calls = []
        complete_puts = []

        target_strikes.each do |strike|
          # Handle calls
          if calls_by_strike[strike]
            complete_calls << calls_by_strike[strike]
          else
            complete_calls << create_synthetic_option(
              strike: strike,
              contract_type: 'CALL',
              underlying_price: underlying_price,
              expiration_date: expiration_date,
              mark: (strike == max_strike ? DEFAULT_MIN_MARK : nil)
            )
          end

          # Handle puts
          if puts_by_strike[strike]
            complete_puts << puts_by_strike[strike]
          else
            complete_puts << create_synthetic_option(
              strike: strike,
              contract_type: 'PUT',
              underlying_price: underlying_price,
              expiration_date: expiration_date,
              mark: (strike == min_strike ? DEFAULT_MIN_MARK : nil)
            )
          end
        end

        [complete_calls, complete_puts]
      end

      def create_synthetic_option(strike:, contract_type:, underlying_price:, expiration_date:, mark: nil)
        DataObjects::Option.new(
          symbol: create_option_symbol(strike, contract_type, expiration_date),
          underlying_symbol: @symbol,
          strike: strike,
          put_call: contract_type,
          mark: mark,
          underlying_price: underlying_price,
          expiration_date: expiration_date,
          days_to_expiration: 0,
          delta: nil,
          open_interest: 0,
          total_volume: 1,
          timestamp: @datetime
        )
      end

      def create_option_symbol(strike, contract_type, expiration_date)
        exp_str = expiration_date.to_s.tr('-', '')
        contract_letter = contract_type[0]
        strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
        "#{@symbol}#{exp_str}#{contract_letter}#{strike_str}"
      end

      def generate_quote(strike_price)
        # TODO: Implement quote generation if needed
        raise NotImplementedError, "get_quote not yet implemented for HistoricalSnapshot"
      end
    end
  end
end
