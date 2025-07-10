module Platypi
  module Loggable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def logger
        Platypi::Logger.logger
      end
    end

    def logger
      self.class.logger
    end

    def log_order(order)
      logger.info("<ORDER | #{Time.now.utc} | #{order.id} | #{order.status}>")
    end

    def log_trade_state(trade_id, state, details = nil)
      msg = "<#{state} | #{Time.now.utc} | #{trade_id}"
      msg += " | #{details}" if details
      msg += ">"

      case state
      when 'TRADE_OPEN'
        logger.info(msg)
      when 'TRADE_FOUND'
        logger.info(msg)
        logger.debug("Strategy: #{details}") if details
      when /ERROR|FAILED/
        logger.error(msg)
      else
        logger.info(msg)
      end
    end
  end
end
