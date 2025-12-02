require_relative 'util'
require_relative 'iron_condor_roller'

# REVIEW: create a TradeState class to encapsulate the state of a trade?
# class TradeState
#   def initialize(trade, markets, logger)
#     @trade = trade
#     @markets = markets
#     @logger = logger

#     @new_call_spread = nil
#     @new_put_spread = nil
#     @new_call_spread_order = nil
#     @new_put_spread_order = nil
#     @close_order = nil

#     @action = nil

#     @tested_window_start = 0
#   end

#   def check_market
#   end
# end

class TradeStateMachine
  DEFAULT_SLEEP_INTERVAL = 30

  CLOSE_TRADE = 'close'.freeze
  CLOSE_FOR_PROFIT = 'close_for_profit'.freeze
  CLOSE_FOR_LOSS = 'close_for_loss'.freeze
  PROCESS_CLOSE = 'process_close'.freeze
  PROCESS_ADJUSTMENT = 'process_adjustment'.freeze
  ADJUST_TRADE = 'adjust'.freeze
  ADJUST_CALL_SIDE = 'adjust_call_side'.freeze
  ADJUST_PUT_SIDE = 'adjust_put_side'.freeze
  START_CALL_SIDE_TIMER = 'start_call_side_timer'.freeze
  START_PUT_SIDE_TIMER = 'start_put_side_timer'.freeze
  DO_NOTHING = 'do_nothing'.freeze

  THIRTY_SECONDS = 30
  FIFTEEN_SECONDS = 15
  TEN_SECONDS = 10
  FIVE_SECONDS = 5
  NO_WAIT = 0

  ADJUSTMENT_TREE = {
    condition: :call_side_tested?,
    true: {
      condition: :adjust_call_side?,
      true: {
        action: ADJUST_CALL_SIDE
      },
      false: {
        action: START_CALL_SIDE_TIMER
      },
    },
    false: {
      condition: :put_side_tested?,
      true: {
        condition: :adjust_put_side?,
        true: {
          action: ADJUST_PUT_SIDE
        },
        false: {
          action: START_PUT_SIDE_TIMER
        }
      },
      false: {
        action: DO_NOTHING
      }
    }
  }

  TREE = {
    condition: :working_close_order?,
    true: {
      action: PROCESS_CLOSE,
    },
    false: {
      condition: :working_adjustment_order?,
      true: {
        action: PROCESS_ADJUSTMENT
      },
      false: {
        condition: :exit_profit?,
        true: {
          action: CLOSE_FOR_PROFIT
        },
        false: {
          condition: :exit_loss?,
          true: {
            action: CLOSE_FOR_LOSS
          },
          false: ADJUSTMENT_TREE
        }
      }
    }
  }

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
    # DEPENDENCIES
    @markets = markets
    @order_manager = order_manager

    # CONFIGURATION
    @exit_prof_thresh = exit_prof_thresh
    @exit_loss_thresh = exit_loss_thresh
    @exit_hour_thresh = exit_hour_thresh
    @est_fees_per_contract = est_fees_per_contract
    @est_commission_per_contract = est_commission_per_contract
    @yellow_zone_delta = yellow_zone_delta
    @red_zone_delta = red_zone_delta
    @price_increment = price_increment
    @max_prof_checks = max_prof_checks
    @sleep_interval = DEFAULT_SLEEP_INTERVAL
    @logger = logger
    @trade_roller = trade_roller

    # TRADE STATE
    @profit_checks = 0
    @trade = nil
    @close_order = nil
    @new_call_spread = nil
    @new_put_spread = nil
    @new_call_spread_order = nil
    @new_put_spread_order = nil
    @action = nil
    @start_tested = 0
    @adjustment_wait_time = adjustment_wait_time # seconds
  end

  attr_reader :markets, :order_manager,
              :exit_prof_thresh, :exit_loss_thresh, :exit_hour_thresh,
              :yellow_zone_delta, :red_zone_delta, :adjustment_wait_time,
              :est_fees_per_contract, :est_commission_per_contract,
              :price_increment, :trade_roller, :action, :logger

  def watch(trade)
    @trade = trade
    while trade.open?
      return if outside_market_hours?

      prices = get_current_spread_prices(@trade)

      next_action = decide(TREE, @trade, prices)
      log_action(next_action, @trade, prices)
      sleep_seconds = execute_action(next_action, @trade, prices)

      wait_for(sleep_seconds)
    end
  end

  def decide(node, trade, prices)
    return node if node[:action]

    if send(node[:condition], trade, prices)
      decide(node[:true], trade, prices)
    else
      decide(node[:false], trade, prices)
    end
  end

  def execute_action(action, trade, prices)
    # NOTE: each action needs to return integer for the sleep time
    case action[:action]
    when PROCESS_CLOSE
      handle_close_order(trade)
    when PROCESS_ADJUSTMENT
      handle_adjustment_order(trade)
    when CLOSE_FOR_PROFIT
      send_close_order(trade, prices)
    when CLOSE_FOR_LOSS
      send_close_order(trade, prices)
    when ADJUST_CALL_SIDE
      adjust_call_side(trade)
    when ADJUST_PUT_SIDE
      adjust_put_side(trade)
    when START_CALL_SIDE_TIMER
      start_tested_timer('CALL')
    when START_PUT_SIDE_TIMER
      start_tested_timer('PUT')
    when DO_NOTHING
      @tested_timer = nil
      DEFAULT_SLEEP_INTERVAL
    end
  end

  #############################
  ### DECISION NODE HELPERS ###
  #############################

  def working_close_order?(trade = nil, prices = nil)
    !@close_order.nil?
  end

  def working_adjustment_order?(trade = nil, prices = nil)
    !@new_call_spread_order.nil? || !@new_put_spread_order.nil?
  end

  def exit_profit?(trade, prices)
    now = Time.now
    today = now.to_date
    current_price = prices[:curr_contract_price]

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

  def exit_loss?(trade, prices)
    now = Time.now
    today = now.to_date
    current_price = prices[:curr_contract_price]

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
      else
        @profit_checks = 0
      end

      @profit_checks >= @max_prof_checks
    else
      false
    end
  end

  def call_side_tested?(trade, prices)
    prices[:call_spread_delta] >= @yellow_zone_delta
  end

  def put_side_tested?(trade, prices)
    prices[:put_spread_delta] >= @yellow_zone_delta
  end

  def adjust_call_side?(trade, prices)
    return false unless @tested_timer && @tested_timer[:side] == 'CALL'
    (Time.now - @tested_timer[:start_time]) >= @adjustment_wait_time
  end

  def adjust_put_side?(trade, prices)
    return false unless @tested_timer && @tested_timer[:side] == 'PUT'
    (Time.now - @tested_timer[:start_time]) >= @adjustment_wait_time
  end

  ###########################
  ### ACTION NODE HELPERS ###
  ###########################

  def start_tested_timer(side)
    unless @tested_timer && @tested_timer[:side] == side
      @tested_timer = {
        side: side,
        start_time: Time.now
      }
    end

    FIVE_SECONDS
  end

  def adjust_call_side(trade)
    move_size = 15
    while move_size > 0
      find_adjustment(
        trade.call_spread,
        trade.put_spread,
        move_size
      ).then do |new_tested_spread, new_untested_spread|
        if new_tested_spread && new_untested_spread
          @new_call_spread = new_tested_spread
          @new_put_spread = new_untested_spread

          @new_call_spread_order = send_rollaway_order(
            trade.call_spread,
            new_tested_spread
          )

          @new_put_spread_order = send_rollup_order(
            trade.put_spread,
            new_untested_spread
          )

          return FIVE_SECONDS
        else
          move_size -= 5
        end
      end
    end

    NO_WAIT
  end

  def adjust_put_side(trade)
    move_size = 15
    while move_size > 0
      find_adjustment(
        trade.put_spread,
        trade.call_spread,
        move_size
      ).then do |new_tested_spread, new_untested_spread|
        if new_tested_spread && new_untested_spread
          @new_put_spread = new_tested_spread
          @new_call_spread = new_untested_spread

          @new_put_spread_order = send_rollaway_order(
            trade.put_spread,
            new_tested_spread
          )

          @new_call_spread_order = send_rollup_order(
            trade.call_spread,
            new_untested_spread
          )

          return FIVE_SECONDS
        else
          move_size -= 5
        end
      end
    end
    NO_WAIT
  end

  def find_adjustment(tested_spread, untested_spread, move_size)
    trade_roller.search(
      tested_spread: tested_spread,
      untested_spread: untested_spread,
      move_size: move_size
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

  def handle_adjustment_order(trade)
    @new_call_spread_order = order_manager.check_order_status(@new_call_spread_order.id) unless @new_call_spread_order.status == 'FILLED'
    @new_put_spread_order = order_manager.check_order_status(@new_put_spread_order.id) unless @new_put_spread_order.status == 'FILLED'

    call_status = @new_call_spread_order.status
    put_status = @new_put_spread_order.status

    if call_status == 'FILLED' && put_status == 'CANCELED'
      @new_put_spread_order = order_manager.send_order(@new_put_spread_order.details)
      NO_WAIT
    elsif call_status == 'CANCELED' && put_status == 'FILLED'
      @new_call_spread_order = order_manager.send_order(@new_call_spread_order.details)
      NO_WAIT
    elsif call_status == 'FILLED' &&  put_status == 'FILLED'
      trade.adjust_call_spread(@new_call_spread, **@new_call_spread_order.details)
      trade.adjust_put_spread(@new_put_spread, **@new_put_spread_order.details)

      @new_call_spread = nil
      @new_put_spread = nil
      @new_call_spread_order = nil
      @new_put_spread_order = nil
      NO_WAIT
    elsif (call_status == 'FILLED' && put_status == 'WORKING') || (call_status == 'WORKING' && put_status == 'FILLED')
      FIVE_SECONDS
    elsif call_status == 'CANCELED' && put_status == 'CANCELED'
      @new_call_spread = nil
      @new_put_spread = nil
      @new_call_spread_order = nil
      @new_put_spread_order = nil
      NO_WAIT
    else
      NO_WAIT
    end
  end

  def handle_close_order(trade)
    @close_order = order_manager.check_order_status(@close_order.id)

    case @close_order.status
    when 'FILLED'
      trade.close(**@close_order.details)
      @close_order = nil
      NO_WAIT
    when 'WORKING'
      FIVE_SECONDS
    when 'CANCELED'
      @close_order = nil
      NO_WAIT
    else
      raise "Unexpected close order status: #{@close_order.status}"
    end
  end

  def send_close_order(trade, prices)
    curr_contract_price = prices[:curr_contract_price]
    @close_order = order_manager.close_iron_condor(trade, price: curr_contract_price)
    unless @close_order.status == 'WORKING'
      raise "Unexpected order status when closing trade: #{@close_order.status}"
    else
      NO_WAIT
    end
  end

  def wait_for(seconds)
    sleep(seconds)
  end

  def outside_market_hours?
    curr_time = Time.now
    (curr_time.hour < 8 && curr_time.min < 25) || (curr_time.hour >= 15 && curr_time.min > 20)
  end

  # REVIEW: delete?
  # def trade_close_price(contract_price)
  #   contract_price * trade.contracts * 100 - \
  #     @est_fees_per_contract * trade.contracts - @est_commission_per_contract * trade.contracts
  # end

  def get_current_spread_prices(trade)
    put_spread_price, put_spread_delta = check_spread(trade.put_spread.short_leg, trade.put_spread.long_leg)
    call_spread_price, call_spread_delta = check_spread(trade.call_spread.short_leg, trade.call_spread.long_leg)

    curr_contract_price = round_up_to_nearest(
      (call_spread_price + put_spread_price).round(2),
      price_increment
    )

    {
      put_spread_price: put_spread_price,
      put_spread_delta: put_spread_delta,
      call_spread_price: call_spread_price,
      call_spread_delta: call_spread_delta,
      curr_contract_price: curr_contract_price
    }
  end

  def check_spread(short_leg, long_leg)
    short_leg_quote = markets.get_quote(short_leg.symbol)
    long_leg_quote = markets.get_quote(long_leg.symbol)

    [(short_leg_quote.mark - long_leg_quote.mark), short_leg_quote.delta.abs]
  end

  def profitability(trade, current_price)
    (trade.open_price - current_price) / trade.open_price
  end

  # REVIEW: delete?
  # def profitable?(trade, current_price)
  #   profitability(trade, current_price) > 0.0
  # end

  # def near_profitable?(trade, current_price)
  #   profit_target_price = trade.open_price * exit_prof_thresh
  #   current_price <= profit_target_price + 0.1
  # end

  def exit_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, exit_hour_thresh, 0, 0)
  end

  def market_open_time_today
    now = Time.now
    Time.new(now.year, now.month, now.day, 8, 30, 0)
  end

  ### LOGGING HELPERS ###
  def log_action(action, trade, prices)
    curr_contract_price = prices[:curr_contract_price]
    call_spread_price = prices[:call_spread_price]
    put_spread_price = prices[:put_spread_price]
    call_spread_delta = prices[:call_spread_delta]
    put_spread_delta = prices[:put_spread_delta]

    @logger.info "Trade #{trade.id} Action: #{action}/" \
                 "#{trade_progress_msg(trade, curr_contract_price, call_spread_price, put_spread_price, call_spread_delta, put_spread_delta)}/" \
                 "#{trade_risk_msg(call_spread_delta, put_spread_delta)}"
  end

  def trade_risk_msg(call_spread_delta, put_spread_delta)
    "CallSpreadDelta: #{call_spread_delta}/PutSpreadDelta: #{put_spread_delta}/TotalDelta: #{(call_spread_delta + put_spread_delta).round(2)}"
  end

  def trade_progress_msg(trade, curr_contract_price, call_spread_price, put_spread_price, call_spread_delta, put_spread_delta)
    "CallSpreadPrice: #{call_spread_price}/PutSpreadPrice: #{put_spread_price}/TotalPrice: #{curr_contract_price}/Profitability: #{(profitability(trade, curr_contract_price) * 100).round(2)}%"
  end
end
