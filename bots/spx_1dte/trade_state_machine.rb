require_relative 'util'
require_relative 'iron_condor_roller'
require_relative 'constants'

class TradeStateMachine
  WAIT_FOR_CLOSE_IRON_CONDOR = 'WAIT_FOR_CLOSE_IRON_CONDOR'.freeze
  WAIT_FOR_CLOSE_CALL_SPREAD = 'WAIT_FOR_CLOSE_CALL_SPREAD'.freeze
  WAIT_FOR_CLOSE_PUT_SPREAD = 'WAIT_FOR_CLOSE_PUT_SPREAD'.freeze
  WAIT_FOR_WORKING_ORDER = 'WAIT_FOR_WORKING_ORDER'.freeze
  DO_NOTHING = 'DO_NOTHING'.freeze

  DEFAULT_WAIT = 30
  THIRTY_SECONDS = 30
  FIFTEEN_SECONDS = 15
  TEN_SECONDS = 10
  FIVE_SECONDS = 5
  NO_WAIT = 0

  DECISION_TABLE = [
    { priority: 1, condition: :working_order?, action: WAIT_FOR_WORKING_ORDER },
    { priority: 2, condition: :exit_iron_condor?, action: EventTypes::CLOSE_IRON_CONDOR },
    { priority: 3, condition: :exit_call_spread?, action: EventTypes::CLOSE_CALL_SPREAD },
    { priority: 4, condition: :exit_put_spread?, action: EventTypes::CLOSE_PUT_SPREAD },
    { priority: 99, condition: :do_nothing, action: DO_NOTHING }
  ]

  def initialize(
    strategy_pricer,
    order_manager,
    yellow_zone_delta: 0.15,
    red_zone_delta: 0.30,
    adjustment_wait_time: 900,
    trade_roller: nil,
    logger: nil
  )
    # DEPENDENCIES
    @strategy_pricer = strategy_pricer
    @order_manager = order_manager

    # CONFIGURATION
    @yellow_zone_delta = yellow_zone_delta
    @red_zone_delta = red_zone_delta

    @sleep_interval = DEFAULT_WAIT
    @logger = logger
    @trade_roller = trade_roller
    @monitoring_window_start = nil
    @monitoring_window_end = nil
    @exit_by_time = nil

    # TRADE STATE
    @last_action = nil
    @trade = nil
    @working_order = nil
    @working_orders = []
    @start_tested = 0
  end

  attr_reader :strategy_pricer, :order_manager,
              :yellow_zone_delta, :red_zone_delta,
              :trade_roller, :last_action, :logger

  def set_monitoring_window(start_time, end_time, exit_by_time)
    @monitoring_window_start = start_time
    @monitoring_window_end = end_time
    @exit_by_time = exit_by_time
  end

  def manage(trade)
    raise "Monitoring window not set" unless @monitoring_window_start && @monitoring_window_end && @exit_by_time

    @trade = trade
    while @trade.open?
      return unless inside_monitoring_window?

      current_strategy = refresh_strategy_price(@trade.strategy)

      decide(@trade, current_strategy).then do |action|
        log_action(action, @trade, current_strategy)
        sleep_seconds = execute_action(action, @trade, current_strategy)
        wait_for(sleep_seconds)
      end
    end
  end

  def decide(trade, strategy)
    DECISION_TABLE.sort_by { |entry| entry[:priority] }.each do |entry|
      return entry[:action] if send(entry[:condition], trade, strategy)
    end
  end

  def execute_action(action, trade, strategy)
    # NOTE: each action needs to return integer for the sleep time
    case action
    when WAIT_FOR_WORKING_ORDER
      handle_close_order(trade, @last_action)
    when EventTypes::CLOSE_IRON_CONDOR
      close_iron_condor(strategy)
    when EventTypes::CLOSE_CALL_SPREAD
      close_call_spread(strategy)
    when EventTypes::CLOSE_PUT_SPREAD
      close_put_spread(strategy)
    when DO_NOTHING
      @last_action = DO_NOTHING
      DEFAULT_WAIT
    end
  end

  #############################
  ### DECISION NODE HELPERS ###
  #############################

  def working_order?(_, _)
    [
      EventTypes::CLOSE_IRON_CONDOR,
      EventTypes::CLOSE_CALL_SPREAD,
      EventTypes::CLOSE_PUT_SPREAD
    ].include?(@last_action)
  end

  def exit_iron_condor?(trade, strategy)
    strategy.is_a?(IronCondor) && exit?(trade, strategy)
  end

  def exit_call_spread?(trade, strategy)
    if strategy.is_a?(IronCondor)
      exit?(trade, strategy.call_spread)
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == 'CALL'
      exit?(trade, strategy)
    else
      false
    end
  end

  def exit_put_spread?(trade, strategy)
    if strategy.is_a?(IronCondor)
      exit?(trade, strategy.put_spread)
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == 'PUT'
      exit?(trade, strategy)
    else
      false
    end
  end

  def exit?(trade, strategy)
    exit_profit?(trade, strategy) || exit_loss?(trade, strategy) || exit_late_profitable?(trade, strategy) || exit_late?(strategy)
  end

  def exit_profit?(trade, strategy)
    if strategy.is_a?(IronCondor)
      strategy.price <= trade.exit_prof_price
    elsif strategy.is_a?(VerticalSpread)
      strategy.price <= trade.exit_prof_price * 0.5
    else
      false
    end
  end

  def exit_loss?(trade, strategy)
    strategy.price >= trade.max_loss_price
  end

  def exit_late_profitable?(trade, strategy)
    Time.now >= @exit_by_time && strategy.price < trade.total_credit_debit
  end

  def exit_late?(strategy)
    Time.now >= @exit_by_time + 3600
  end

  ###########################
  ### ACTION NODE HELPERS ###
  ###########################

  def do_nothing(_, _)
    true
  end

  def handle_close_order(trade, event_type = nil)
    @working_order = order_manager.check_order_status(@working_order.id)

    case @working_order.status
    when OrderStatuses::FILLED
      trade.save_event(@last_action, **@working_order.details)
      @working_order = nil
      @last_action = nil
      NO_WAIT
    when OrderStatuses::WORKING
      FIVE_SECONDS
    when OrderStatuses::CANCELED
      @working_order = nil
      @last_action = nil
      NO_WAIT
    else
      raise "Unexpected close order status: #{@working_order.status}"
    end
  end

  def close_iron_condor(strategy)
    raise "Must be an IronCondor strategy to close iron condor" unless strategy.is_a?(IronCondor)

    @working_order = order_manager.close_iron_condor(strategy)
    unless @working_order.status == OrderStatuses::WORKING
      raise "Unexpected order status when closing trade: #{@working_order.status}"
    else
      @last_action = EventTypes::CLOSE_IRON_CONDOR
      NO_WAIT
    end
  end

  def close_put_spread(strategy)
    strat = if strategy.is_a?(IronCondor)
      strategy.put_spread
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::PUT
      strategy
    else
      raise "Must be a put spread to close put spread"
    end

    close_spread(strat)
    @last_action = EventTypes::CLOSE_PUT_SPREAD
    NO_WAIT
  end

  def close_call_spread(strategy)
    strat = if strategy.is_a?(IronCondor)
      strategy.call_spread
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::CALL
      strategy
    else
      raise "Must be a call spread to close call spread"
    end

    close_spread(strat)
    @last_action = EventTypes::CLOSE_CALL_SPREAD
    NO_WAIT
  end

  def close_spread(strategy)
    @working_order = order_manager.close_spread(strategy)
    raise "Unexpected order status when closing spread: #{@working_order.status}" unless @working_order.status == OrderStatuses::WORKING
  end

  # REVIEW: adjustment logic

  # def start_tested_timer(side)
  #   unless @tested_timer && @tested_timer[:side] == side
  #     @tested_timer = {
  #       side: side,
  #       start_time: Time.now
  #     }
  #   end

  #   FIVE_SECONDS
  # end

  # def adjust_call_side(trade)
  #   move_size = 15
  #   while move_size > 0
  #     find_adjustment(
  #       trade.call_spread,
  #       trade.put_spread,
  #       move_size
  #     ).then do |new_tested_spread, new_untested_spread|
  #       if new_tested_spread && new_untested_spread
  #         @new_call_spread = new_tested_spread
  #         @new_put_spread = new_untested_spread

  #         @new_call_spread_order = send_rollaway_order(
  #           trade.call_spread,
  #           new_tested_spread
  #         )

  #         @new_put_spread_order = send_rollup_order(
  #           trade.put_spread,
  #           new_untested_spread
  #         )

  #         return FIVE_SECONDS
  #       else
  #         move_size -= 5
  #       end
  #     end
  #   end

  #   NO_WAIT
  # end

  # def adjust_put_side(trade)
  #   move_size = 15
  #   while move_size > 0
  #     find_adjustment(
  #       trade.put_spread,
  #       trade.call_spread,
  #       move_size
  #     ).then do |new_tested_spread, new_untested_spread|
  #       if new_tested_spread && new_untested_spread
  #         @new_put_spread = new_tested_spread
  #         @new_call_spread = new_untested_spread

  #         @new_put_spread_order = send_rollaway_order(
  #           trade.put_spread,
  #           new_tested_spread
  #         )

  #         @new_call_spread_order = send_rollup_order(
  #           trade.call_spread,
  #           new_untested_spread
  #         )

  #         return FIVE_SECONDS
  #       else
  #         move_size -= 5
  #       end
  #     end
  #   end
  #   NO_WAIT
  # end

  # def find_adjustment(tested_spread, untested_spread, move_size)
  #   trade_roller.search(
  #     tested_spread: tested_spread,
  #     untested_spread: untested_spread,
  #     move_size: move_size
  #   )
  # end

  # def send_rollaway_order(tested_spread, new_tested_spread)
  #   order_manager.rollaway_spread(
  #     tested_spread,
  #     new_tested_spread,
  #     price: round_up_to_nearest(tested_spread.price - new_tested_spread.price, price_increment)
  #   )
  # end

  # def send_rollup_order(untested_spread, new_untested_spread)
  #   order_manager.rollup_spread(
  #     untested_spread,
  #     new_untested_spread,
  #     price: round_down_to_nearest(new_untested_spread.price - untested_spread.price, price_increment)
  #   )
  # end

  # def handle_adjustment_order(trade)
  #   @new_call_spread_order = order_manager.check_order_status(@new_call_spread_order.id) unless @new_call_spread_order.status == 'FILLED'
  #   @new_put_spread_order = order_manager.check_order_status(@new_put_spread_order.id) unless @new_put_spread_order.status == 'FILLED'

  #   call_status = @new_call_spread_order.status
  #   put_status = @new_put_spread_order.status

  #   if call_status == 'FILLED' && put_status == 'CANCELED'
  #     @new_put_spread_order = order_manager.send_order(@new_put_spread_order.details)
  #     NO_WAIT
  #   elsif call_status == 'CANCELED' && put_status == 'FILLED'
  #     @new_call_spread_order = order_manager.send_order(@new_call_spread_order.details)
  #     NO_WAIT
  #   elsif call_status == 'FILLED' &&  put_status == 'FILLED'
  #     trade.save_event("ADJUST_CALL_SPREAD", **@new_call_spread_order.details)
  #     trade.save_event("ADJUST_PUT_SPREAD", **@new_put_spread_order.details)

  #     @new_call_spread = nil
  #     @new_put_spread = nil
  #     @new_call_spread_order = nil
  #     @new_put_spread_order = nil
  #     NO_WAIT
  #   elsif (call_status == 'FILLED' && put_status == 'WORKING') || (call_status == 'WORKING' && put_status == 'FILLED')
  #     FIVE_SECONDS
  #   elsif call_status == 'CANCELED' && put_status == 'CANCELED'
  #     @new_call_spread = nil
  #     @new_put_spread = nil
  #     @new_call_spread_order = nil
  #     @new_put_spread_order = nil
  #     NO_WAIT
  #   else
  #     NO_WAIT
  #   end
  # end

  ####################
  ### UTIL METHODS ###
  ####################

  def wait_for(seconds)
    sleep(seconds)
  end

  def inside_monitoring_window?
    curr_time = Time.now
    curr_time >= @monitoring_window_start && curr_time <= @monitoring_window_end
  end

  def refresh_strategy_price(strategy)
    strategy_pricer.refresh(strategy)
  end

  #######################
  ### LOGGING HELPERS ###
  #######################

  def log_action(action, trade, strategy)
    @logger.info "Trade #{trade.id} / Action: #{action} / " \
                 "#{trade_progress_msg(strategy)}/" \
                 "#{strategy_risk_msg(strategy)}"
  end

  def strategy_risk_msg(strategy)
    if strategy.is_a?(IronCondor)
      risk_msg(strategy.call_spread.delta.abs, strategy.put_spread.delta.abs)
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::CALL
      risk_msg(strategy.delta.abs, 0.0)
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::PUT
      risk_msg(0.0, strategy.delta.abs)
    else
      risk_msg(0.0, 0.0)
    end
  end

  def risk_msg(call_spread_delta, put_spread_delta)
    "CallSpreadDelta: #{call_spread_delta.round(3)}/PutSpreadDelta: #{put_spread_delta.round(3)}/TotalDelta: #{(call_spread_delta + put_spread_delta).round(3)}"
  end

  def trade_progress_msg(strategy)
    if strategy.is_a?(IronCondor)
      "Strategy: #{strategy.class.name} / CallSpreadPrice: #{strategy.call_spread.price.round(3)}/PutSpreadPrice: #{strategy.put_spread.price.round(3)}/TotalPrice: #{strategy.price.round(3)}"
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::CALL
      "Strategy: #{strategy.class.name} / CallSpreadPrice: #{strategy.price.round(3)} / PutSpreadPrice: - / TotalPrice: #{strategy.price.round(3)}"
    elsif strategy.is_a?(VerticalSpread) && strategy.contract_type == StrategyTypes::PUT
      "Strategy: #{strategy.class.name} / CallSpreadPrice: - / PutSpreadPrice: #{strategy.price.round(3)} / TotalPrice: #{strategy.price.round(3)}"
    else
      "Strategy: - / CallSpreadPrice: - / PutSpreadPrice: - / TotalPrice: -"
    end
  end
end
