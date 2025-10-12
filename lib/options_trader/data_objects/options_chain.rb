require 'csv'

module OptionsTrader
  module DataObjects
    class OptionsChain
      def initialize(symbol:, underlying_price: nil, call_opts: [], put_opts: [])
        @symbol = symbol
        @underlying_price = underlying_price
        @call_opts = call_opts
        @put_opts = put_opts
      end

      attr_reader :symbol, :underlying_price, :call_opts, :put_opts

      # Writes CSV for this options chain. Parameters similar to the previous
      # model-level helper: expiration_date, underlying_symbol, end_time,
      # window_minutes, and optional file_path. Returns the written file_path.
      def to_csv(dir: nil)
        options = Array(call_opts) + Array(put_opts)

        symbol_for_filename = symbol || options.first&.symbol || underlying_symbol
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        default_filename = "option_chain_#{symbol_for_filename}_#{timestamp}.csv"
        dir = dir ? dir : Dir.pwd
        file_path ||= File.join(dir, default_filename)

        CSV.open(file_path, 'w', headers: true) do |csv|
          csv << %w[symbol underlying_symbol underlying_price expiration_date strike contract_type mark high_price low_price open_price close_price volume valid_time]

          options.each do |opt|
            csv << [
              opt.symbol,
              opt.underlying_symbol,
              opt.underlying_price,
              opt.expiration_date,
              opt.strike,
              opt.put_call,
              opt.mark,
              opt.high,
              opt.low,
              opt.open,
              opt.close,
              opt.total_volume,
              opt.timestamp,
            ]
          end
        end

        file_path
      end
    end
  end
end
