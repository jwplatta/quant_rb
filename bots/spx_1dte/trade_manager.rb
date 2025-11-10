require_relative 'util'

class TradeManager
  DEFAULT_SLEEP_INTERVAL = 30

  def initialize(
    markets,
    order_manager,
    exit_prof_thresh: 0.35, exit_loss_thresh: 3.0, exit_hour_thresh: 12,
    est_fees_per_contract: 0.0, est_commission_per_contract: 0.0,
    price_increment: 0.05, max_prof_checks: 30, logger: nil
  )
    @markets = markets
    @order_manager = order_manager
    @exit_prof_thresh = exit_prof_thresh
    @exit_loss_thresh = exit_loss_thresh
    @exit_hour_thresh = exit_hour_thresh
    @est_fees_per_contract = est_fees_per_contract
    @est_commission_per_contract = est_commission_per_contract
    @price_increment = price_increment
    @max_prof_checks = max_prof_checks
    @prof_checks = 0
    @logger = logger

    @trade = nil
    @adjusting_trade = false
    @closing_trade = false
    @sleep_interval = DEFAULT_SLEEP_INTERVAL
  end

  attr_reader :markets, :order_manager, :exit_prof_thresh, :exit_loss_thresh, :exit_hour_thresh, :trade,
                :est_fees_per_contract, :est_commission_per_contract, :price_increment, :logger

  def watch(trade)
    @trade = trade
    @prof_checks = 0

    while trade.open?
      return if outside_market_hours?

      call_spread_price, call_spread_delta = check_spread(trade.call_spread.short_leg, trade.call_spread.long_leg)
      put_spread_price, put_spread_delta = check_spread(trade.put_spread.short_leg, trade.put_spread.long_leg)
      curr_contract_price = (call_spread_price + put_spread_price).round(2)

      curr_contract_price = round_down_to_nearest(curr_contract_price, price_increment)
      close_price = trade_close_price(curr_contract_price)

      logger.info trade_progress_msg(
        trade, curr_contract_price, call_spread_price, put_spread_price, call_spread_delta, put_spread_delta
      )
      logger.info trade_risk_msg(call_spread_delta, put_spread_delta)

      if order_manager.order_sent
        status, order_dtls = order_manager.check_order_status(trade.id)
        logger.info "Order status: #{status}"

        if status == 'FILLED'
          if @closing_trade
            trade.set_close(**order_dtls)
            logger.info "Trade closed at price: #{order_dtls[:price]}"
          # elsif @adjusting_trade
          #   trade.set_adjustment(**order_dtls)
          else
            raise "Unknown order type filled."
          end

          @sleep_interval = 0
          @closing_trade = false
          @adjusting_trade = false
        elsif status == 'WORKING' && order_manager.check_fill_count < 3
          logger.info "Order working. Checking in #{@sleep_interval} seconds"
          @sleep_interval = 5
        elsif status == 'WORKING'
          logger.info "Order working too long. Canceling order and re-evaluating trade."
          order_manager.cancel_order(trade.id)
          @closing_trade = false
          @adjusting_trade = false
          @sleep_interval = 0
        end
      elsif exit_profit?(curr_contract_price, trade)
        logger.info "Profit target reached. Closing trade at price: #{curr_contract_price}."

        order_status = order_manager.send_order(:close, trade.close_order_args(curr_contract_price))
        if order_status == 'WORKING'
          @closing_trade = true
          @sleep_interval = 5
        elsif order_status == 'REJECTED'
          @sleep_interval = 0
        else
          raise "Unexpected order status when closing trade: #{order_status}"
        end
      elsif exit_loss?(curr_contract_price, trade)
        logger.info "Loss target reached. Closing trade. Current price: #{curr_contract_price}, Max loss price: #{trade.max_loss_price}."

        order_status = order_manager.send_order(:close, trade.close_order_args(curr_contract_price))
        if order_status == 'WORKING'
          @closing_trade = true
          @sleep_interval = 5
        elsif order_status == 'REJECTED'
          @sleep_interval = 0
        else
          raise "Unexpected order status when closing trade: #{order_status}"
        end
      else
        # NOTE: maybe you want to include some other conditions here. Is the market moving a lot today? Is the VIX or the VIX1D up?
        # Are you approaching the exit time threshold?
        @sleep_interval = 30
        logger.info "Continuing to watch trade. Checking again in #{@sleep_interval} seconds."
      end

      sleep(@sleep_interval) unless trade.closed?
    end
  end

  def reset
    # REVIEW: might be an unnecessary helper, but ensures the status is cleared
    # between trades
    @trade = nil
    @adjusting_trade = false
    @closing_trade = false
    @prof_checks = 0
  end

  def outside_market_hours?
    curr_time = Time.now
    (curr_time.hour < 8 && curr_time.min < 25) || (curr_time.hour >= 15 && curr_time.min > 20)
  end

  def trade_close_price(contract_price)
    contract_price * trade.contracts * 100 - \
      @est_fees_per_contract * trade.contracts - @est_commission_per_contract * trade.contracts
  end

  def check_spread(short_leg, long_leg)
    short_leg_quote = markets.get_quote(short_leg.symbol)
    long_leg_quote = markets.get_quote(long_leg.symbol)

    [(short_leg_quote.mark - long_leg_quote.mark).round(2), short_leg_quote.delta.abs]
  end

  def profitability(trade, current_price)
    (trade.open_price - current_price) / trade.open_price
  end

  def profitable?(trade, current_price)
    profitability(trade, current_price) > 0.0
  end

  def near_profitable?(trade, current_price)
    profit_target_price = trade.open_price * exit_prof_thresh
    current_price <= profit_target_price + 0.1
  end

  def trade_risk_msg(call_spread_delta, put_spread_delta)
    "CallSpreadDelta: #{call_spread_delta}/PutSpreadDelta: #{put_spread_delta}/TotalDelta: #{(call_spread_delta + put_spread_delta).round(2)}"
  end

  def trade_progress_msg(trade, curr_contract_price, call_spread_price, put_spread_price, call_spread_delta, put_spread_delta)
    "CallSpreadPrice: #{call_spread_price}/PutSpreadPrice: #{put_spread_price}/TotalPrice: #{curr_contract_price}/Profitability: #{(profitability(trade, curr_contract_price) * 100).round(2)}%"
  end

  def exit_profit?(current_price, trade)
    now = Time.now
    today = now.to_date

    if today < trade.expiration_date
      # NOTE: if day before expiration, then trade was just opened
      false
    elsif now >= market_open_time_today && now < exit_time_today
      current_price <= exit_prof_thresh
    elsif now >= exit_time_today
      # NOTE: after exit hour threshold, be more aggressive about exiting

      profitability(trade, current_price) >= 0.0
    else
      false
    end
  end

  def exit_loss?(current_price, trade)
    now = Time.now
    today = now.to_date

    if today < trade.expiration_date
      # NOTE: if day before expiration, then trade was just opened
      false
    elsif now >= market_open_time_today && now < exit_time_today
      current_price >= exit_loss_thresh
    # NOTE: think this condition just get handled with the exit_profit
    elsif now >= exit_time_today
      # NOTE: basically if the price isn't improving after 15 minutes, then just exit
      if profitability(trade, current_price) <= 0.0
        @prof_checks += 1
        logger.info "Profitability check failed at #{now}. Profitability checks: #{@prof_checks}"
      else
        logger.info "Profitability check passed at #{now}."
        @prof_checks = 0
      end

      @prof_checks >= @max_prof_checks
    else
      false
    end
  end

  def adjust_trade?(current_price, trade)
    # TODO: implement adjustment logic
  end

  def exit_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, exit_hour_thresh, 0, 0)
  end

  def market_open_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, 8, 30, 0)
  end

  def time_adjusted_profit_target(target_profit_price, expiration_date)
    raise "Expiration date must be a Date object" unless expiration_date.is_a?(Date)

    if Date.today == expiration_date
      hour = Time.now.hour

      if hour < exit_hour_thresh - 1
        target_profit_price
      elsif hour >= exit_hour_thresh - 1 and hour < exit_hour_thresh
        target_profit_price * 0.5
      elsif hour >= exit_hour_thresh && hour < 14
        target_profit_price * 0.01
      else
        0.0
      end
    elsif Date.today < expiration_date
      target_profit_price
    else
      raise "Trade has expired!"
    end
  end
end
