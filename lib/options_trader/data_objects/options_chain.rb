module OptionsTrader
  module DataObjects
    class OptionsChain
      def initialize(symbol:, call_opts: [], put_opts: [])
        @symbol = symbol
        @call_opts = call_opts
        @put_opts = put_opts
      end

      attr_reader :symbol, :call_opts, :put_opts
    end
  end
end
