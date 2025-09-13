module OptionsTrader
  module Backtest
    class HistoricalSnapshotIterator
      include Enumerable

      def initialize(underlying_price_history, snapshot_class, **snapshot_kwargs)
        @underlying_price_history = underlying_price_history
        @snapshot_class = snapshot_class
        @snapshot_kwargs = snapshot_kwargs
        @snapshots = []
      end

      attr_reader :snapshots

      def steps
        @steps ||= @underlying_price_history.map { |candle| candle.datetime }
      end

      def each
        return enum_for(:each) unless block_given?

        @underlying_price_history.each_with_index do |candle, index|
          snapshot = @snapshot_class.new(
            
            datetime: candle.datetime,
            symbol: candle.symbol,
            spot_price: candle.close,
            **@snapshot_kwargs
          )

          @snapshots << snapshot
          yield snapshot
        end
      end
    end
  end
end
