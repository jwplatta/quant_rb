# id         | bigint                         |           | not null | nextval('price_history_id_seq'::regclass)
#  symbol     | character varying              |           | not null |
#  open       | numeric(10,2)                  |           |          |
#  close      | numeric(10,2)                  |           |          |
#  high       | numeric(10,2)                  |           |          |
#  low        | numeric(10,2)                  |           |          |
#  volume     | integer                        |           | not null | 0
#  interval   | character varying              |           | not null |
#  valid_time | timestamp without time zone    |           | not null |
#  created_at | timestamp(6) without time zone |           | not null |
#  updated_at | timestamp(6) without time zone |           | not null |

module OptionsTrader
  module DataObjects
    class Quote
      def initialize(symbol:, open:, close:, high:, low:, volume:, valid_time:, asset_type: nil, **kwargs)
        @symbol = symbol
        @open = open
        @close = close
        @high = high
        @low = low
        @volume = volume
        @valid_time = valid_time
        @asset_type = asset_type
      end

      attr_reader :symbol, :open, :close, :high, :low, :volume, :valid_time, :asset_type

      def mark(method: 'close')
        case method
        when 'close'
          close
        when 'open'
          open
        when 'high'
          high
        when 'low'
          low
        when 'avg'
          (open + close + high + low) / 4.0
        else
          close
        end
      end
    end
  end
end
