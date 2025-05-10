# frozen_string_literal: true

require_relative 'iron_condor_order'
require_relative 'put_spread'
require_relative 'call_spread'
require_relative 'call_option'
require_relative 'put_option'

class TradeFactory
  TRADE_TYPES = %w[
    IRON_CONDOR
    CALL_SPREAD
    PUT_SPREAD
    CALL_OPTION
    PUT_OPTION
  ].freeze

  class << self
    def build(trade_type, **kwargs)
      case trade_type
      when 'IRON_CONDOR'
        IronCondorOrder.new(**kwargs)
      when 'CALL_SPREAD'
        CallSpread.new(**kwargs)
      when 'PUT_SPREAD'
        PutSpread.new(**kwargs)
      when 'CALL_OPTION'
        CallOption.new(**kwargs)
      when 'PUT_OPTION'
        PutOption.new(**kwargs)
      else
        raise "Unsupported trade type: #{trade_type}"
      end
    end
  end
end
