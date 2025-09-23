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
    end
  end
end
