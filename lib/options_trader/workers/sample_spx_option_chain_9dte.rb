require 'sidekiq'
require 'date'
require 'csv'
require 'fileutils'

require_relative '../../options_trader'

module OptionsTrader
  module Workers
    class SampleSpxOptionChain9DTE
      include Sidekiq::Worker
      include OptionsTrader::Loggable

      UNDERLYING_SYMBOL = '$SPX'
      INDEX_SYMBOLS = ['$VIX', '$VIX9D', '$VIX3M', '$VVIX', '$SKEW', '$SPX'].freeze

      def perform(start_expiration_date, valid_time)
        @start_expiration_date = adjust_to_business_day(Date.parse(start_expiration_date))
        @end_expiration_date = adjust_to_business_day(@start_expiration_date + 9)
        @valid_time = Time.parse(valid_time).utc

        @samples_base_path = ENV['SAMPLES_FLATFILES_PATH']
        raise "SAMPLES_FLATFILES_PATH environment variable not set" unless @samples_base_path

        schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
        @markets_service = OptionsTrader::Services::Markets.new(provider: schwab_provider)

        logger.info "Processing SPX option chain sample for #{@start_expiration_date} to #{@end_expiration_date} at #{@valid_time}"

        process_option_chain(UNDERLYING_SYMBOL)
        process_index_quotes

        logger.info "Sample collection completed"
      end

      private

      def process_option_chain(symbol)
        logger.info "Getting option chain for #{symbol}"

        begin
          opt_chain = @markets_service.get_option_chain(
            symbol,
            contract_type: 'ALL',
            strike_range: 'ALL',
            from_date: @start_expiration_date,
            to_date: @end_expiration_date
          )

          if opt_chain.nil?
            logger.warn "No option chain returned for #{symbol}"
            return
          end

          write_option_chain_to_csv(symbol, opt_chain)

        rescue StandardError => e
          logger.error "Failed to get option chain for #{symbol}: #{e.message}"
          logger.error e.backtrace.join("\n")
        end
      end

      def process_index_quotes
        logger.info "Getting quotes for index symbols: #{INDEX_SYMBOLS.join(', ')}"

        begin
          quotes = @markets_service.get_quotes(INDEX_SYMBOLS)

          if quotes.nil? || quotes.empty?
            logger.warn "No quotes returned for index symbols"
            return
          end

          quotes.each do |quote|
            write_quote_to_csv(quote)
          end

        rescue StandardError => e
          logger.error "Failed to get quotes for index symbols: #{e.message}"
          logger.error e.backtrace.join("\n")
        end
      end

      def write_option_chain_to_csv(symbol, opt_chain)
        file_path = build_file_path('options', symbol)
        ensure_directory_exists(File.dirname(file_path))

        write_headers = !File.exist?(file_path)

        CSV.open(file_path, 'a') do |csv|
          if write_headers
            csv << option_chain_headers
          end

          opt_chain.call_opts.each do |opt|
            csv << build_option_record(opt, opt_chain.underlying_price)
          end

          opt_chain.put_opts.each do |opt|
            csv << build_option_record(opt, opt_chain.underlying_price)
          end
        end

        logger.info "Wrote option chain data to #{file_path} (#{opt_chain.call_opts.length} calls, #{opt_chain.put_opts.length} puts)"
      end

      def write_quote_to_csv(quote)
        symbol = quote.symbol
        file_path = build_file_path('indexes', symbol)
        ensure_directory_exists(File.dirname(file_path))

        write_headers = !File.exist?(file_path)

        CSV.open(file_path, 'a') do |csv|
          if write_headers
            csv << quote_headers
          end

          csv << build_quote_record(quote)
        end

        logger.info "Wrote quote data to #{file_path}"
      end

      def build_file_path(type, symbol)
        date = @valid_time.utc.to_date
        year = date.year
        month = date.month.to_s.rjust(2, '0')
        day = date.day.to_s.rjust(2, '0')

        File.join(@samples_base_path, type, year.to_s, month, day, "#{symbol}.csv")
      end

      def ensure_directory_exists(dir_path)
        FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
      end

      def option_chain_headers
        [
          'symbol', 'root_symbol', 'underlying_symbol', 'expiration_date', 'strike',
          'contract_type', 'bid', 'ask', 'mark', 'last_price', 'underlying_price',
          'delta', 'theta', 'vega', 'gamma', 'rho', 'open_interest', 'volume',
          'bid_size', 'ask_size', 'option_root', 'expiration_type', 'intrinsic_value',
          'extrinsic_value', 'time_value', 'volatility', 'high_52_week', 'low_52_week',
          'high_price', 'low_price', 'open_price', 'close_price', 'valid_time'
        ]
      end

      def quote_headers
        [
          'symbol', 'valid_time', 'open', 'close', 'high', 'low', 'volume'
        ]
      end

      def build_option_record(option, underlying_price)
        [
          option.symbol,
          option.option_root,
          option.underlying_symbol,
          option.expiration_date,
          option.strike,
          option.put_call,
          option.bid,
          option.ask,
          option.mark,
          option.last,
          underlying_price,
          round_decimal(option.delta),
          round_decimal(option.theta),
          round_decimal(option.vega),
          round_decimal(option.gamma),
          round_decimal(option.rho),
          option.open_interest,
          option.total_volume,
          option.bid_size,
          option.ask_size,
          option.option_root,
          option.expiration_type,
          option.intrinsic_value,
          option.extrinsic_value,
          option.time_value,
          round_decimal(option.volatility),
          option.high_52_week,
          option.low_52_week,
          option.high_price,
          option.low_price,
          option.open_price,
          option.close_price,
          @valid_time.utc.iso8601
        ]
      end

      def build_quote_record(quote)
        [
          quote.symbol,
          @valid_time.utc.iso8601,
          quote.open_price,
          quote.close_price,
          quote.high_price,
          quote.low_price,
          quote.total_volume
        ]
      end

      def round_decimal(value)
        return nil if value.nil?
        value.round(3)
      end

      def convert_time_to_utc(time)
        return nil if time.nil?
        time.respond_to?(:utc) ? time.utc.iso8601 : time
      end

      def adjust_to_business_day(date)
        case date.wday
        when 0 # Sunday - move to next Monday
          date + 1
        when 6 # Saturday - move to next Monday
          date + 2
        else # Monday-Friday
          date
        end
      end
    end
  end
end
