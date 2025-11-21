require_relative 'util'
require_relative 'iron_condor_roller'

class TradeManager
  DEFAULT_SLEEP_INTERVAL = 30
  OPEN_TRADE = 'open'.freeze
  CLOSE_TRADE = 'close'.freeze
  ADJUST_TRADE = 'adjust'.freeze
  ACTIONS = [
    OPEN_TRADE,
    CLOSE_TRADE,
    ADJUST_TRADE,
  ].freeze

  THIRTY_SECONDS = 30
  FIFTEEN_SECONDS = 15
  TEN_SECONDS = 10
  FIVE_SECONDS = 5
  NO_SLEEP = 0


  def initialize(
    markets,
    order_manager,
    exit_prof_thresh: 0.35, exit_loss_thresh: 3.0, exit_hour_thresh: 12,
    est_fees_per_contract: 0.0, est_commission_per_contract: 0.0,
    yellow_zone_delta: 0.15,
    red_zone_delta: 0.30,
    adjustment_wait_time: 900,
    trade_roller: nil,
    price_increment: 0.05,
    max_prof_checks: 30,
    logger: nil
  )
    @markets = markets
    @order_manager = order_manager

    @exit_prof_thresh = exit_prof_thresh
    @exit_loss_thresh = exit_loss_thresh
    @exit_hour_thresh = exit_hour_thresh
    @est_fees_per_contract = est_fees_per_contract
    @est_commission_per_contract = est_commission_per_contract
    @yellow_zone_delta = yellow_zone_delta
    @red_zone_delta = red_zone_delta
    @price_increment = price_increment
    @max_prof_checks = max_prof_checks
    @profit_checks = 0
    @logger = logger
    @trade_roller = trade_roller

    @trade = nil
    @close_order = nil
    @new_call_spread = nil
    @new_put_spread = nil
    @new_call_spread_order = nil
    @new_put_spread_order = nil
    @action = nil
    @tested_window_start = 0
    @adjustment_wait_time = adjustment_wait_time # seconds
    @sleep_interval = DEFAULT_SLEEP_INTERVAL
  end

  attr_reader :markets, :order_manager,
              :exit_prof_thresh, :exit_loss_thresh, :exit_hour_thresh, :trade,
              :yellow_zone_delta, :red_zone_delta, :adjustment_wait_time,
              :est_fees_per_contract, :est_commission_per_contract,
              :price_increment, :trade_roller, :action, :logger

  def watch(trade)
    @trade = trade
    @profit_checks = 0

    while trade.open?
      return if outside_market_hours?
      put_spread_price, put_spread_delta = check_spread(trade.put_spread.short_leg, trade.put_spread.long_leg)
      call_spread_price, call_spread_delta = check_spread(trade.call_spread.short_leg, trade.call_spread.long_leg)

      curr_contract_price = round_up_to_nearest(
        (call_spread_price + put_spread_price).round(2),
        price_increment
      )

      logger.info trade_progress_msg(
        trade, curr_contract_price,
        call_spread_price, put_spread_price,
        call_spread_delta, put_spread_delta
      )
      logger.info trade_risk_msg(call_spread_delta, put_spread_delta)

      if action == CLOSE_TRADE
        @close_order = order_manager.check_order_status(@close_order.id)
        logger.info "Order status: #{@close_order.status}"

        if @close_order.status == 'FILLED'
          logger.info "Trade closed at price: #{@close_order.details[:price]}"
          trade.close(**@close_order.details)
          @action = nil
          @close_order = nil
        elsif @close_order.status == 'WORKING'
          logger.info "Order working. Checking in #{FIVE_SECONDS} seconds"
          wait_for(FIVE_SECONDS)
        elsif @close_order.status == 'CANCELED'
          logger.info "Close order was canceled. Resetting action."
          @action = nil
          @close_order = nil
        end
      elsif action == ADJUST_TRADE
        @new_call_spread_order = order_manager.check_order_status(@new_call_spread_order.id) unless @new_call_spread_order.status == 'FILLED'
        @new_put_spread_order = order_manager.check_order_status(@new_put_spread_order.id) unless @new_put_spread_order.status == 'FILLED'
        logger.info "Adjusted call spread order status: #{@new_call_spread_order.status}"
        logger.info "Adjusted put spread order status: #{@new_put_spread_order.status}"

        if @new_call_spread_order.status == 'FILLED' && @new_put_spread_order.status == 'CANCELED'
          order_manager.send_order(@new_put_spread_order.details)
        elsif @new_call_spread_order.status == 'CANCELED' && @new_put_spread_order.status == 'FILLED'
          order_manager.send_order(@new_call_spread_order.details)
        elsif @new_call_spread_order.status == 'FILLED' && @new_put_spread_order.status == 'FILLED'
          logger.info "Adjustment completed."
          trade.adjust_call_spread(@new_call_spread, **@new_call_spread_order.details)
          trade.adjust_put_spread(@new_put_spread, **@new_put_spread_order.details)

          @action = nil
          @new_call_spread = nil
          @new_put_spread = nil
          @new_call_spread_order = nil
          @new_put_spread_order = nil
        elsif @new_call_spread_order.status == 'FILLED' and @new_put_spread_order.status == 'WORKING'
          wait_for(FIVE_SECONDS)
        elsif @new_call_spread_order.status == 'WORKING' and @new_put_spread_order.status == 'FILLED'
          wait_for(FIVE_SECONDS)
        elsif @new_call_spread_order.status == 'CANCELED' && @new_put_spread_order.status == 'CANCELED'
          logger.info "Both adjustment orders were canceled. Resetting action."
          @action = nil
          @new_call_spread = nil
          @new_put_spread = nil
          @new_call_spread_order = nil
          @new_put_spread_order = nil
        end
      elsif exit_profit?(curr_contract_price, trade)
        logger.info "Profit target reached. Closing trade at price: #{curr_contract_price}."
        send_close_order(trade, curr_contract_price)
      elsif exit_loss?(curr_contract_price, trade)
        logger.info "Loss target reached. Closing trade. Current price: #{curr_contract_price}, Max loss price: #{trade.max_loss_price}."
        send_close_order(trade, curr_contract_price)
      elsif call_spread_delta >= yellow_zone_delta
        logger.info "Call side tested."

        if @tested_window_start.nil?
          @tested_window_start = Time.now
          wait_for(FIVE_SECONDS)
        elsif Time.now - @tested_window_start > @adjustment_wait_time
          @new_call_spread, @new_put_spread = find_adjustment(trade.call_spread, trade.put_spread)
          if @new_call_spread && @new_put_spread
            @new_call_spread_order = send_rollaway_order(trade.call_spread, @new_call_spread)
            @new_put_spread_order = send_rollup_order(trade.put_spread,  @new_put_spread)
            if @new_call_spread_order && @new_put_spread_order
              @action = ADJUST_TRADE
            else
              raise "Error sending adjustment orders!"
            end
          end
        else
          wait_for(FIVE_SECONDS)
        end
      elsif put_spread_delta >= yellow_zone_delta
        logger.info "Put side tested."

        if @tested_window_start.nil?
          @tested_window_start = Time.now
          wait_for(FIVE_SECONDS)
        elsif Time.now - @tested_window_start > @adjustment_wait_time
          @new_put_spread, @new_call_spread = find_adjustment(trade.put_spread, trade.call_spread)

          if @new_put_spread && @new_call_spread
            @new_put_spread_order = send_rollup_order(trade.put_spread, @new_put_spread)
            @new_call_spread_order = send_rollaway_order(trade.call_spread, @new_call_spread)
            if @new_put_spread_order && @new_call_spread_order
              @action = ADJUST_TRADE
            else
              raise "Error sending adjustment orders!"
            end
          end
        else
          wait_for(FIVE_SECONDS)
        end
      else
        # NOTE: maybe you want to include some other conditions here. Is the market moving a lot today? Is the VIX or the VIX1D up?
        # Are you approaching the exit time threshold?
        @tested_window_start = 0 # reset the tested window
        @action = nil
        wait_for(THIRTY_SECONDS)
      end
    end
  end

  def find_adjustment(tested_spread, untested_spread)
    trade_roller.search(
      tested_spread: tested_spread,
      untested_spread: untested_spread,
      move_size: 5
    )
  end

  def send_rollaway_order(tested_spread, new_tested_spread)
    order_manager.rollaway_spread(
      tested_spread,
      new_tested_spread,
      price: round_up_to_nearest(tested_spread.price - new_tested_spread.price, price_increment)
    )
  end

  def send_rollup_order(untested_spread, new_untested_spread)
    order_manager.rollup_spread(
      untested_spread,
      new_untested_spread,
      price: round_down_to_nearest(new_untested_spread.price - untested_spread.price, price_increment)
    )
  end

  def send_close_order(trade, curr_contract_price)
    @close_order = order_manager.close_iron_condor(trade, price: curr_contract_price)
    if @close_order.status == 'WORKING'
      @action = CLOSE_TRADE
    else
      raise "Unexpected order status when closing trade: #{@close_order.status}"
    end
  end

  def wait_for(seconds)
    sleep(seconds)
  end

  def reset
    # REVIEW: might be an unnecessary helper,
    # but ensures the status is cleared between trades
    @trade = nil
    @action = nil
    @profit_checks = 0
  end

  def outside_market_hours?
    return false
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

    [(short_leg_quote.mark - long_leg_quote.mark), short_leg_quote.delta.abs]
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
      # NOTE: if the price isn't improving after an extended period of time, then just exit.
      if profitability(trade, current_price) <= 0.0
        @profit_checks += 1
        logger.info "Profitability check failed at #{now}. Profitability checks: #{@profit_checks}"
      else
        logger.info "Profitability check passed at #{now}."
        @profit_checks = 0
      end

      @profit_checks >= @max_prof_checks
    else
      false
    end
  end

  def exit_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, exit_hour_thresh, 0, 0)
  end

  def market_open_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, 8, 30, 0)
  end
end
