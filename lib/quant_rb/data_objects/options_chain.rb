# frozen_string_literal: true

require "csv"

module QuantRb
  module DataObjects
    class OptionsChain
      def initialize(symbol:, underlying_price: nil, call_opts: [], put_opts: [])
        @symbol          = symbol
        @underlying_price = underlying_price
        @call_opts       = Array(call_opts)
        @put_opts        = Array(put_opts)
      end

      attr_reader :symbol, :underlying_price, :call_opts, :put_opts

      # All options (calls + puts) as a flat array.
      def all_options
        call_opts + put_opts
      end

      # Options for a specific expiration date.
      def options_for(expiration_date)
        all_options.select { |o| o.expiration_date == expiration_date }
      end

      # Available expiration dates across all options.
      def expiration_dates
        all_options.map(&:expiration_date).uniq.sort
      end

      def empty?
        call_opts.empty? && put_opts.empty?
      end

      def size
        call_opts.size + put_opts.size
      end

      def to_csv(dir: nil)
        options = all_options
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        dir ||= Dir.pwd
        file_path = File.join(dir, "option_chain_#{symbol}_#{timestamp}.csv")

        CSV.open(file_path, "w", headers: true) do |csv|
          csv << %w[symbol underlying_symbol underlying_price expiration_date strike
                    contract_type mark bid ask delta gamma theta vega rho
                    open_interest total_volume volatility]
          options.each do |opt|
            csv << [
              opt.symbol, opt.underlying_symbol, opt.underlying_price,
              opt.expiration_date, opt.strike, opt.put_call,
              opt.mark, opt.bid, opt.ask,
              opt.delta, opt.gamma, opt.theta, opt.vega, opt.rho,
              opt.open_interest, opt.total_volume, opt.volatility
            ]
          end
        end

        file_path
      end
    end
  end
end
