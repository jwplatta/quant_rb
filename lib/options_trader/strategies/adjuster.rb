# NOTE: use the command pattern
module OptionsTrader
  class Adjuster
    class << self
      def adjust(strategy, **kwargs)
        case strategy.type
        when 'ironcondor'
          IronCondorAdjuster.find_new_strategy(strategy, **kwargs)
        when 'putspread'
          PutSpreadAdjuster.find_new_strategy(strategy, **kwargs)
        when 'callspread'
          CallSpreadAdjuster.find_new_strategy(strategy, **kwargs)
        else
          raise "Unsupported strategy type for adjustment: #{strategy.type}"
        end
      end
    end
  end
end
