module OptionsTrader
  module Services
    # Generates historical option chains for a specific point in time using LOCF (Last Observation Carried Forward).
    # Creates synthetic options for missing strikes and enriches chains with market features (VIX, skew, etc.).
    class HistoricalSnapshot
      class MissingPriceRecordError < StandardError; end

      DEFAULT_STALENESS_THRESHOLD_MINUTES = 5

      # @param symbol [String] Underlying symbol (e.g., 'SPXW')
      # @param valid_time [Time] Point in time for the historical snapshot
      def initialize(valid_time:, window: DEFAULT_STALENESS_THRESHOLD_MINUTES)
        @valid_time = valid_time
        @window = window
      end

      attr_reader :valid_time, :window

      def get_quote(symbol, **kwargs)
        interval = kwargs[:interval] || '5min'
        generate_quote(symbol, interval: interval, window: window)
      end

      def get_quotes(symbols, **kwargs)
        interval = kwargs[:interval] || '5min'

        symbols.map do |symbol|
          generate_quote(symbol, interval: interval, window: window)
        end
      end

      # Retrieves a complete option chain with synthetic options for missing strikes.
      # Optionally enriches with market features like VIX, skew, etc.
      #
      # @param symbol [String] Underlying symbol
      # @param expiration_date [Date] Option expiration date
      # @return [DataObjects::OptionsChain] Complete option chain with calls and puts
      def get_option_chain(symbol, **kwargs)
        expiration_date = kwargs[:expiration_date]
        raise ArgumentError, "expiration_date is required" if expiration_date.nil?

        generate_options_chain(symbol, expiration_date)
      end

      private

      # Core method that fetches historical data, generates synthetic options, interpolates prices,
      # and enforces monotonicity to create a complete, arbitrage-free option chain.
      def generate_options_chain(underlying_symbol, expiration_date)
        # Step 1: Fetch existing options using LOCF
        # If features are requested, use the enriched query; otherwise use the basic query
        call_opts, put_opts = OptionChainHistory.fetch_with_locf(
          expiration_date: expiration_date,
          underlying_symbol: underlying_symbol,
          end_time: valid_time,
          window: window
        ).then do |records|
          call_opts = []
          put_opts = []

          records.each do |record|
            option = build_option_from_record(record)
            if option.put_call == 'CALL'
              call_opts << option
            elsif option.put_call == 'PUT'
              put_opts << option
            end
          end

          [call_opts, put_opts]
        end

        DataObjects::OptionsChain.new(
          symbol: underlying_symbol,
          underlying_price: call_opts.first&.underlying_price || put_opts.first&.underlying_price || 0.0,
          call_opts: call_opts,
          put_opts: put_opts
        )
      end

      # Extracts market feature values (VIX, skew, etc.) from a database record
      # by filtering out standard option fields.
      def build_option_from_record(record)
        DataObjects::Option.new(
          symbol: record['symbol'],
          underlying_symbol: record['underlying_symbol'],
          strike: record['strike'].to_i,
          put_call: record['contract_type'],
          mark: record['mark'].to_f,
          underlying_price: record['underlying_price'].to_f,
          expiration_date: record['expiration_date'],
          days_to_expiration: days_to_expiration_from_record(record),
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

      def days_to_expiration_from_record(record)
        if record['dte']
          record['dte'].to_i
        else
          (Date.parse(record['expiration_date']) - record['valid_time'].to_date).to_i
        end
      end

      def generate_quote(symbol, window: 5, interval: '5min')
        # def self.latest_for_symbol(symbol, end_time, start_time = nil, interval = '5min')
        # end_time: valid_time,
        # window_minutes: window
        price_record = PriceHistory.fetch_latest(symbol, valid_time, window: window, interval: interval)

        raise MissingPriceRecordError, "No valid price record found for symbol #{symbol} at #{valid_time}" if price_record.nil?

        price_record
      end
    end
  end
end
