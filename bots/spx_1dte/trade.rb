require 'securerandom'
require_relative 'trades_file_manager'
require_relative 'data_objects'
require_relative 'constants'

class Trade
  class << self
    def open_trade
      TradesFileManager.instance.open_trade
    end
  end

  NEW_STATUS = 'NEW'.freeze
  OPEN_STATUS = 'OPEN'.freeze
  CLOSED_STATUS = 'CLOSED'.freeze
  STATUSES = [NEW_STATUS, OPEN_STATUS, CLOSED_STATUS].freeze

  def initialize(
    id: nil,
    status: NEW_STATUS,
    exit_prof_price: 0.5,
    exit_loss_mult: 3.0,
    price_increment: 0.05,
    trade_history: []
  )
    @id = id || SecureRandom.uuid().delete('-')
    @price_increment = price_increment

    @exit_prof_price = exit_prof_price
    @exit_loss_mult = exit_loss_mult

    @status = status

    @current_positions = nil
    @trade_history = trade_history
  end

  attr_reader :id, :exit_prof_price, :exit_loss_mult, :status,
    :trade_history, :price_increment

  def symbols
    positions = current_positions

    positions[:call_positions].select { |_, qty| qty != 0 }.keys +
      positions[:put_positions].select { |_, qty| qty != 0 }.keys
  end

  def profit_loss
    total_credit_debit - total_fees - total_commissions
  end

  def save_event(event_type, **order_dtls)
    @trade_history << {}.tap do |e|
      e[:event_type] = event_type
      e[:fees] = order_dtls[:fees]
      e[:commissions] = order_dtls[:commissions]
      e[:price] = order_dtls[:price]
      e[:quantity] = order_dtls[:quantity]
      e[:credit_debit_type] = order_dtls[:credit_debit]
      e[:credit_debit_amount] = calc_credit_debit(e[:price], e[:quantity], order_dtls[:credit_debit])
      if event_type == EventTypes::OPEN_IRON_CONDOR || event_type == EventTypes::CLOSE_IRON_CONDOR
        e[:put_short_symbol] = order_dtls[:put_short_symbol]
        e[:put_long_symbol] = order_dtls[:put_long_symbol]
        e[:call_short_symbol] = order_dtls[:call_short_symbol]
        e[:call_long_symbol] = order_dtls[:call_long_symbol]
      elsif event_type == EventTypes::OPEN_PUT_SPREAD || event_type == EventTypes::CLOSE_PUT_SPREAD
        e[:put_short_symbol] = order_dtls[:short_leg_symbol]
        e[:put_long_symbol] = order_dtls[:long_leg_symbol]
      elsif event_type == EventTypes::OPEN_CALL_SPREAD || event_type == EventTypes::CLOSE_CALL_SPREAD
        e[:call_short_symbol] = order_dtls[:short_leg_symbol]
        e[:call_long_symbol] = order_dtls[:long_leg_symbol]
      end
      e[:timestamp] = Time.now
    end
    # REVIEW: should just update the positions when we save the event?
    # Replaying the trade history could be slow for long lived trades.
    @current_positions = nil # NOTE: reset cached positions
    current_positions

    if @status == NEW_STATUS
      set_status
      trades_file_manager.create(self)
    else
      set_status
      trades_file_manager.update(self)
    end
  end

  def set_status
    if position_open?
      @status = OPEN_STATUS
    elsif position_closed?
      @status = CLOSED_STATUS
    else
      @status = NEW_STATUS
    end
  end

  def open?
    status == OPEN_STATUS
  end

  def closed?
    status == CLOSED_STATUS
  end

  ##################################
  ### STRATEGY DETECTION METHODS ###
  ##################################

  def strategy
    [open_iron_condor, open_call_spread, open_put_spread, null_strategy].find { |s| s }
  end

  def position_closed?
    !position_open?
  end

  def position_open?
    !open_call_spread.nil? || !open_put_spread.nil?
  end

  def open_iron_condor
    call_spread = open_call_spread
    put_spread = open_put_spread

    if call_spread.nil? || put_spread.nil?
      nil
    else
      IronCondor.new(
        put_spread: put_spread,
        call_spread: call_spread,
        quantity: [call_spread.quantity, put_spread.quantity].min,
        expiration_date: put_spread.expiration_date
      )
    end
  end

  def open_call_spread
    open_spread(current_positions[:call_positions], 'CALL')
  end

  def open_put_spread
    open_spread(current_positions[:put_positions], 'PUT')
  end

  def open_spread(positions, contract_type)
    short_leg = positions.find { |_, qty| qty < 0 }
    return nil if short_leg.nil?

    long_leg = positions.find { |symbol, qty| symbol != short_leg[0] && qty > 0 }

    raise "Spread quantity not equal" if !long_leg.nil? && !short_leg.nil? && (short_leg[1].abs != long_leg[1].abs)

    if !long_leg.nil? && !short_leg.nil?
      new_vertical_spread(short_leg[1].abs, short_leg[0], long_leg[0], contract_type)
    else
      nil
    end
  end

  ###########################
  ### POSITION MANAGEMENT ###
  ###########################

  def current_positions
    # NOTE: we can always find the current positions by replaying the trade history
    return @current_positions if @current_positions

    all_positions = trade_history.sort_by { |event| event[:timestamp] }.reduce(
      { call_positions: {}, put_positions: {} }
    ) do |positions, event|
      case event[:event_type]
      when EventTypes::OPEN_IRON_CONDOR
        open_iron_condor_position(positions, event)
      when EventTypes::CLOSE_IRON_CONDOR
        close_iron_condor_position(positions, event)
      when EventTypes::OPEN_PUT_SPREAD
        open_put_spread_position(positions, event)
      when EventTypes::CLOSE_PUT_SPREAD
        close_put_spread_position(positions, event)
      when EventTypes::OPEN_CALL_SPREAD
        open_call_spread_position(positions, event)
      when EventTypes::CLOSE_CALL_SPREAD
        close_call_spread_position(positions, event)
      else
        raise "Unknown event type: #{event[:event_type]}"
      end
    end

    # Filter out positions with zero quantity
    @current_positions = {
      call_positions: all_positions[:call_positions].select { |_, qty| qty != 0 },
      put_positions: all_positions[:put_positions].select { |_, qty| qty != 0 }
    }
  end

  def open_iron_condor_position(positions, event)
    call_positions = positions[:call_positions].clone
    put_positions = positions[:put_positions].clone

    positions[:call_positions] = decrease_position(call_positions, event[:call_short_symbol], event[:quantity]).then do |cp|
      increase_position(cp, event[:call_long_symbol], event[:quantity])
    end
    positions[:put_positions] = decrease_position(put_positions, event[:put_short_symbol], event[:quantity]).then do |pp|
      increase_position(pp, event[:put_long_symbol], event[:quantity])
    end

    positions
  end

  def close_iron_condor_position(positions, event)
    call_positions = positions[:call_positions].clone
    put_positions = positions[:put_positions].clone

    positions[:call_positions] = increase_position(call_positions, event[:call_short_symbol], event[:quantity]).then do |cp|
      decrease_position(cp, event[:call_long_symbol], event[:quantity])
    end
    positions[:put_positions] = increase_position(put_positions, event[:put_short_symbol], event[:quantity]).then do |pp|
      decrease_position(pp, event[:put_long_symbol], event[:quantity])
    end

    positions
  end

  def open_put_spread_position(positions, event)
    put_positions = positions[:put_positions].clone
    positions[:put_positions] = decrease_position(put_positions, event[:put_short_symbol], event[:quantity]).then do |pp|
      increase_position(pp, event[:put_long_symbol], event[:quantity])
    end
    positions
  end

  def close_put_spread_position(positions, event)
    put_positions = positions[:put_positions].clone
    positions[:put_positions] = increase_position(put_positions, event[:put_short_symbol], event[:quantity]).then do |pp|
      decrease_position(pp, event[:put_long_symbol], event[:quantity])
    end
    positions
  end

  def open_call_spread_position(positions, event)
    call_positions = positions[:call_positions].clone
    positions[:call_positions] = decrease_position(call_positions, event[:call_short_symbol], event[:quantity]).then do |cp|
      increase_position(cp, event[:call_long_symbol], event[:quantity])
    end
    positions
  end

  def close_call_spread_position(positions, event)
    call_positions = positions[:call_positions].clone
    positions[:call_positions] = increase_position(call_positions, event[:call_short_symbol], event[:quantity]).then do |cp|
      decrease_position(cp, event[:call_long_symbol], event[:quantity])
    end
    positions
  end

  def decrease_position(positions, symbol, quantity_change)
    if positions.has_key?(symbol)
      positions[symbol] -= quantity_change
    else
      positions[symbol] = -quantity_change
    end
    positions
  end

  def increase_position(positions, symbol, quantity_change)
    if positions.has_key?(symbol)
      positions[symbol] += quantity_change
    else
      positions[symbol] = quantity_change
    end
    positions
  end

  ###########################
  ### TRADE VALUE METHODS ###
  ###########################

  def open_event
    @trade_history.min_by { |event| event[:timestamp] }
  end

  def last_event
    @trade_history.max_by { |event| event[:timestamp] }
  end

  def open_credit
    open_price * open_event[:quantity] * 100 - open_fees - open_commissions
  end

  def open_price
    open_event[:price]
  end

  def open_fees
    open_event[:fees]
  end

  def open_commissions
    open_event[:commissions]
  end

  def total_credit_debit
    @trade_history.reduce(0) { |sum, event| sum + (event[:credit_debit_amount] || 0) }
  end

  def total_fees
    @trade_history.reduce(0) { |sum, event| sum + (event[:fees] || 0) }
  end

  def total_commissions
    @trade_history.reduce(0) { |sum, event| sum + (event[:commissions] || 0) }
  end

  def calc_credit_debit(price, quantity, credit_debit_type)
    if credit_debit_type == :credit
      price * quantity * 100
    else
      price * quantity * -100
    end
  end

  def close_loss_price
    open_price * exit_loss_mult
  end

  def max_loss_price
    round_down_to_nearest(open_price * exit_loss_mult)
  end

  def break_even_price
    # this is per iron condor
    round_up_to_nearest((open_price * 100 + 2 * open_fees + 2 * open_commissions) / 100.0)
  end

  def target_profit_price
    # this is per iron condor
    round_down_to_nearest((open_price * 100 - open_fees - open_commissions) * exit_prof_price / 100.0)
  end

  def round_up_to_nearest(value)
    ((value / @price_increment).ceil * @price_increment).round(2)
  end

  def round_down_to_nearest(value)
    ((value / @price_increment).floor * @price_increment).round(2)
  end

  def to_h
    {
      id: id,
      status: status,
      exit_prof_price: exit_prof_price,
      exit_loss_mult: exit_loss_mult,
      price_increment: price_increment,
      trade_history: trade_history.map(&:to_h)
    }
  end

  private

  def null_strategy
    NullStrategy.new
  end

  def new_vertical_spread(quantity, short_leg_symbol, long_leg_symbol, contract_type)
    expiration_date = parse_expiration_date(short_leg_symbol)
    VerticalSpread.new(
      quantity: quantity,
      short_leg: OptionLeg.new(
        symbol: short_leg_symbol, contract_type: contract_type, expiration_date: expiration_date
      ),
      long_leg: OptionLeg.new(
        symbol: long_leg_symbol, contract_type: contract_type, expiration_date: expiration_date
      ),
      contract_type: contract_type,
      expiration_date: expiration_date
    )
  end

  def parse_expiration_date(symbol)
    # NOTE: example "SPXW  251211P06785000" where the expiration date is "251211" -> "2025-12-11"
    match = symbol.match(/\s(\d{6})/)
    raise "Invalid symbol format" unless match

    date_str = match[1]
    year = "20#{date_str[0..1]}"
    month = date_str[2..3]
    day = date_str[4..5]
    Date.parse("#{year}-#{month}-#{day}")
  end

  def trades_file_manager
    TradesFileManager.instance
  end
end
