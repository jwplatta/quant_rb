require 'sidekiq'
require 'date'

require_relative '../../options_trader'

module OptionsTrader
  module Workers
    class SampleOptionsChain
      include Sidekiq::Worker
      include OptionsTrader::Schwab
      include OptionsTrader::Loggable

      def perform(underlying_symbol, expiration_date, valid_time)
        expiration_date = Date.parse(expiration_date)
        valid_time = Time.parse(valid_time)

        logger.info "Processing SampleOptionsChain for #{underlying_symbol} on #{expiration_date} at #{valid_time}"

        download_options_chain_for_date(underlying_symbol, expiration_date, valid_time)
      end

      private

      def download_options_chain_for_date(underlying_symbol, expiration_date, valid_time)
        logger.info "Downloading option chain for #{underlying_symbol} expiration date: #{expiration_date}"

        begin
          opt_chain = option_chain(
            underlying_symbol,
            contract_type: 'ALL',
            to_date: expiration_date,
            from_date: expiration_date,
            strike_range: 'ALL'
          )

          if opt_chain.nil?
            logger.warn "No option chain returned for #{underlying_symbol} on #{expiration_date}"
            return
          end

          underlying_price = opt_chain.underlying_price
          option_records = []

          opt_chain.call_opts.each do |opt|
            option_records << build_option_record(opt, valid_time, underlying_price)
          end

          opt_chain.put_opts.each do |opt|
            option_records << build_option_record(opt, valid_time, underlying_price)
          end

          # NOTE: Bulk insert
          if option_records.any?
            OptionsTrader::OptionChainHistory.insert_all(option_records)
            logger.info "Batch saved #{opt_chain.call_opts.length} calls and #{opt_chain.put_opts.length} puts for #{underlying_symbol} on #{expiration_date}"
          end

        rescue StandardError => e
          logger.error "Failed to download option chain for #{underlying_symbol} on #{expiration_date}: #{e.message}"
          logger.error e.backtrace.join("\n")
        end
      end

      def build_option_record(option, valid_time, underlying_price)
        {
          symbol: option.symbol,
          root_symbol: option.option_root,
          underlying_symbol: option.underlying_symbol,
          expiration_date: option.expiration_date,
          strike: option.strike,
          contract_type: option.put_call,
          bid: option.bid,
          ask: option.ask,
          mark: option.mark,
          last_price: option.last,
          underlying_price: underlying_price,
          delta: round_decimal(option.delta),
          theta: round_decimal(option.theta),
          vega: round_decimal(option.vega),
          gamma: round_decimal(option.gamma),
          rho: round_decimal(option.rho),
          open_interest: option.open_interest,
          volume: option.total_volume,
          bid_size: option.bid_size,
          ask_size: option.ask_size,
          option_root: option.option_root,
          expiration_type: option.expiration_type,
          intrinsic_value: option.intrinsic_value,
          extrinsic_value: option.extrinsic_value,
          time_value: option.time_value,
          volatility: round_decimal(option.volatility),
          high_52_week: option.high_52_week,
          low_52_week: option.low_52_week,
          high_price: option.high_price,
          low_price: option.low_price,
          open_price: option.open_price,
          close_price: option.close_price,
          valid_time: valid_time,
          transaction_time: Time.current
        }
      end

      def round_decimal(value)
        return nil if value.nil?
        value.round(3)
      end
    end
  end
end
