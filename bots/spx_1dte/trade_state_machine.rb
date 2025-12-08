require_relative 'util'
require_relative 'iron_condor_roller'

# REVIEW: create a TradeState class to encapsulate the state of a trade?
# class TradeState
#   def initialize(trade, logger)
#     @trade = trade
#     @logger = logger

#     @new_call_spread = nil
#     @new_put_spread = nil
#     @new_call_spread_order = nil
#     @new_put_spread_order = nil
#     @close_order = nil

#     @last_action = nil

#     @tested_window_start = 0
#   end

#   def check_market
#   end
# end

class TradeStateMachine
  OPEN_TRADE = 'open'.freeze
  OPEN_IRON_CONDOR = 'open_iron_condor'.freeze
  OPEN_PUT_SPREAD = 'open_put_spread'.freeze
  OPEN_CALL_SPREAD = 'open_call_spread'.freeze
  CLOSE_IRON_CONDOR = 'close_iron_condor'.freeze
  CLOSE_PUT_SPREAD = 'close_put_spread'.freeze
  CLOSE_CALL_SPREAD = 'close_call_spread'.freeze
  CLOSE_FOR_PROFIT = 'close_for_profit'.freeze
  CLOSE_FOR_LOSS = 'close_for_loss'.freeze
  WAIT_FOR_CLOSE_IRON_CONDOR = 'wait_for_close_iron_condor'.freeze
  WAIT_FOR_CLOSE_CALL_SPREAD = 'wait_for_close_call_spread'.freeze
  WAIT_FOR_CLOSE_PUT_SPREAD = 'wait_for_close_put_spread'.freeze
  DO_NOTHING = 'do_nothing'.freeze

  DEFAULT_WAIT = 30
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

  EXIT_TREE = {
    condition: :exit_profit?,
    true: {
      action: CLOSE_IRON_CONDOR
    },
    false: {
      condition: :exit_loss?,
      true: {
        action: CLOSE_IRON_CONDOR
      },
      false: {
        condition: :exit_call_spread?,
        true: {
          action: CLOSE_CALL_SPREAD
        },
        false: {
          condition: :exit_put_spread?,
          true: {
            action: CLOSE_PUT_SPREAD
          },
          false: ADJUSTMENT_TREE
        }
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
      false: EXIT_TREE
    }
  }

  def initialize(
    strategy_pricer,
    order_manager,
    exit_prof_price: 0.35,
    exit_loss_mult: 3.0,
    est_fees_per_contract: 0.0,
    est_commission_per_contract: 0.0,
    yellow_zone_delta: 0.15,
    red_zone_delta: 0.30,
    adjustment_wait_time: 900,
    trade_roller: nil,
    price_increment: 0.05,
    max_prof_checks: 30,
    logger: nil
  )
    # DEPENDENCIES
    @strategy_pricer = strategy_pricer
    @order_manager = order_manager

    # CONFIGURATION
    @exit_prof_price = exit_prof_price
    @exit_loss_mult = exit_loss_mult
    @est_fees_per_contract = est_fees_per_contract
    @est_commission_per_contract = est_commission_per_contract
    @yellow_zone_delta = yellow_zone_delta
    @red_zone_delta = red_zone_delta
    @price_increment = price_increment
    @max_prof_checks = max_prof_checks
    @sleep_interval = DEFAULT_WAIT
    @logger = logger
    @trade_roller = trade_roller
    @monitoring_window_start = nil
    @monitoring_window_end = nil
    @exit_by_time = nil

    # TRADE STATE
    @last_action = nil
    @profit_checks = 0
    @trade = nil
    @close_order = nil
    @working_order = nil
    @new_call_spread = nil
    @new_put_spread = nil
    @new_call_spread_order = nil
    @new_put_spread_order = nil
    @last_action = nil
    @start_tested = 0
    @adjustment_wait_time = adjustment_wait_time # seconds
  end

  attr_reader :strategy_pricer, :order_manager,
              :exit_prof_price, :exit_loss_mult,
              :yellow_zone_delta, :red_zone_delta, :adjustment_wait_time,
              :est_fees_per_contract, :est_commission_per_contract,
              :price_increment, :trade_roller, :action, :logger

  def set_monitoring_window(start_time, end_time, exit_by_time)
    @monitoring_window_start = start_time
    @monitoring_window_end = end_time
    @exit_by_time = exit_by_time
  end

  def manage(trade)
    raise "Monitoring window not set" unless @monitoring_window_start && @monitoring_window_end && @exit_by_time

    @trade = trade
    while @trade.open?
      return if outside_monitoring_window?

      strategy = refresh_strategy_price(@trade.strategy)

      decide(TREE, strategy).then do |action|
        log_action(action, @trade, strategy)
        sleep_seconds = execute_action(action, @trade, strategy)
        wait_for(sleep_seconds)
      end
    end
  end

  def decide(node, strategy)
    return node if node[:action]

    if send(node[:condition], strategy)
      decide(node[:true], strategy)
    else
      decide(node[:false], strategy)
    end
  end

  def execute_action(action, trade, strategy)
    # NOTE: each action needs to return integer for the sleep time
    case action[:action]
    when WAIT_FOR_CLOSE_IRON_CONDOR
      @last_action = CLOSE_IRON_CONDOR
      handle_close_order(trade, @last_action)
    when WAIT_FOR_CLOSE_CALL_SPREAD
      @last_action = CLOSE_CALL_SPREAD
      handle_close_order(trade, @last_action)
    when WAIT_FOR_CLOSE_PUT_SPREAD
      @last_action = CLOSE_PUT_SPREAD
      handle_close_order(trade, @last_action)
    when CLOSE_IRON_CONDOR
      @last_action = CLOSE_IRON_CONDOR
      close_iron_condor(trade, market_context)
    when CLOSE_CALL_SPREAD
      @last_action = CLOSE_CALL_SPREAD
      close_call_spread(trade, market_context)
    when CLOSE_PUT_SPREAD
      @last_action = CLOSE_PUT_SPREAD
      close_put_spread(trade, market_context)
    when DO_NOTHING
      @last_action = DO_NOTHING
      @tested_timer = nil
      DEFAULT_WAIT
    end
  end

  #############################
  ### DECISION NODE HELPERS ###
  #############################

  def closing_iron_condor?
    @last_action == CLOSE_IRON_CONDOR && !@working_order.nil?
  end

  def closing_call_spread?
    @last_action == CLOSE_CALL_SPREAD && !@working_order.nil?
  end

  def closing_put_spread?
    @last_action == CLOSE_PUT_SPREAD && !@working_order.nil?
  end

  def exit_iron_condor?(strategy)
    if strategy.is_a? IronCondor
      strategy.price <= exit_prof_price
    else
      false
    end
  end

  def exit_call_spread?(strategy)
    if strategy.is_a? IronCondor
      strategy.call_spread.price <= exit_prof_price * 0.5
    elsif strategy.is_a? VerticalSpread && strategy.contract_type == 'CALL'
      strategy.price <= exit_prof_price * 0.5
    else
      false
    end
  end

  def exit_put_spread?(strategy)
    if strategy.is_a? IronCondor
      strategy.put_spread.price <= exit_prof_price * 0.5
    elsif strategy.is_a? VerticalSpread && strategy.contract_type == 'PUT'
      strategy.price <= exit_prof_price * 0.5
    else
      false
    end
  end

  def exit_loss?(strategy)
    strategy.price >= exit_loss_mult * trade.open_price
  end

  def exit_late_profitable?(strategy)
    now = Time.now
    now >= @exit_by_time && strategy.price >= 0.0
  end

  def exit_late?(strategy)
    now >= @exit_by_time + 3600
  end

  ###########################
  ### ACTION NODE HELPERS ###
  ###########################

  def handle_close_order(trade, event_type = nil)
    @working_order = order_manager.check_order_status(@working_order.id)

    case @working_order.status
    when 'FILLED'
      trade.save_event(event_type, **@working_order.details)
      @working_order = nil
      @last_action = nil
      NO_WAIT
    when 'WORKING'
      FIVE_SECONDS
    when 'CANCELED'
      @working_order = nil
      @last_action = nil
      NO_WAIT
    else
      raise "Unexpected close order status: #{@working_order.status}"
    end
  end

  def close_iron_condor(strategy)
    @working_order = order_manager.close_iron_condor(strategy)
    unless @working_order.status == 'WORKING'
      raise "Unexpected order status when closing trade: #{@working_order.status}"
    else
      @last_action = CLOSE_IRON_CONDOR
      NO_WAIT
    end
  end

  def close_put_spread(strategy)
    @working_order = order_manager.close_spread(strategy)
    unless @working_order.status == 'WORKING'
      raise "Unexpected order status when closing spread: #{@working_order.status}"
    else
      @last_action = CLOSE_PUT_SPREAD
      NO_WAIT
    end
  end

  def close_call_spread(strategy)
    @working_order = order_manager.close_spread(strategy)
    unless @working_order.status == 'WORKING'
      raise "Unexpected order status when closing spread: #{@working_order.status}"
    else
      @last_action = CLOSE_CALL_SPREAD
      NO_WAIT
    end
  end

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
      trade.save_event("ADJUST_CALL_SPREAD", **@new_call_spread_order.details)
      trade.save_event("ADJUST_PUT_SPREAD", **@new_put_spread_order.details)

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

  ####################
  ### UTIL METHODS ###
  ####################

  def wait_for(seconds)
    sleep(seconds)
  end

  def outside_monitoring_window?
    curr_time = Time.now
    curr_time < @monitoring_window_start || curr_time > @monitoring_window_end
  end

  def update_strategy_price(strategy)
    # NOTE: this should be something like "get current market conditions"
    # It should get all the relevant data points - price, delta, gamma, open interest, etc.
    # It should calculate any indicators like GEX
    if strategy.is_a? IronCondor
      put_spread_price, put_spread_delta = check_spread(strategy.put_spread.short_leg, strategy.put_spread.long_leg)
      call_spread_price, call_spread_delta = check_spread(strategy.call_spread.short_leg, strategy.call_spread.long_leg)
    elsif strategy.is_a? VerticalSpread && strategy.contract_type == 'PUT'
      put_spread_price, put_spread_delta = check_spread(strategy.short_leg, strategy.long_leg)
      call_spread_price = 0.0
      call_spread_delta = 0.0
    elsif strategy.is_a? VerticalSpread && strategy.contract_type == 'CALL'
      call_spread_price, call_spread_delta = check_spread(strategy.short_leg, strategy.long_leg)
      put_spread_price = 0.0
      put_spread_delta = 0.0
    else
      put_spread_price = 0.0
      put_spread_delta = 0.0
      call_spread_price = 0.0
      call_spread_delta = 0.0
    end

    curr_contract_price = round_up_to_nearest(
      (call_spread_price + put_spread_price).round(2),
      price_increment
    )

    {
      put_spread_price: put_spread_price,
      put_spread_delta: put_spread_delta,
      call_spread_price: call_spread_price,
      call_spread_delta: call_spread_delta,
    }
  end

  def refresh_strategy_price(strategy)
    strategy_pricer.refresh(strategy)
  end

  def profitability(trade, current_price)
    (trade.open_price - current_price) / trade.open_price
  end

  ### LOGGING HELPERS ###
  def log_action(action, trade, market_context)
    curr_contract_price = market_context[:curr_contract_price]
    call_spread_price = market_context[:call_spread_price]
    put_spread_price = market_context[:put_spread_price]
    call_spread_delta = market_context[:call_spread_delta]
    put_spread_delta = market_context[:put_spread_delta]

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
