require 'securerandom'
require_relative 'trades_file_manager'
require_relative 'data_objects'

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
    init_strategy: nil,
    status: NEW_STATUS,
    expiration_date:,
    contracts: 1,
    exit_prof_thresh: 0.5,
    exit_loss_thresh: 3.0,
    price_increment: 0.05,
    call_positions: {},
    put_positions: {},
    trade_history: []
  )
    @id = id || SecureRandom.uuid().delete('-')
    @init_strategy = init_strategy
    @contracts = contracts
    @expiration_date = expiration_date
    @price_increment = price_increment

    @exit_prof_thresh = exit_prof_thresh
    @exit_loss_thresh = exit_loss_thresh

    @status = status

    @call_positions = call_positions
    @put_positions = put_positions
    @trade_history = trade_history
  end

  attr_reader :id, :init_strategy, :expiration_date,
    :open_price, :close_price, :exit_prof_thresh, :exit_loss_thresh, :status,
    :contracts, :trade_history, :call_positions, :put_positions, :price_increment

  def symbols
    @call_positions.select { |_, qty| qty != 0 }.keys +
      @put_positions.select { |_, qty| qty != 0 }.keys
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
      e[:put_short_leg_symbol] = order_dtls[:put_short_symbol] if order_dtls.key?(:put_short_symbol)
      e[:put_long_leg_symbol] = order_dtls[:put_long_symbol] if order_dtls.key?(:put_long_symbol)
      e[:call_short_leg_symbol] = order_dtls[:call_short_symbol] if order_dtls.key?(:call_short_symbol)
      e[:call_long_leg_symbol] = order_dtls[:call_long_symbol] if order_dtls.key?(:call_long_symbol)
      e[:timestamp] = Time.now.utc.iso8601
    end

    if @status == NEW_STATUS
      set_status
      trades_file_manager.create(self)
    else
      set_status
      trades_file_manager.update(self)
    end
  end

  def set_status
    if open_position?
      @status = OPEN_STATUS
    elsif all_positions_closed?
      @status = CLOSED_STATUS
    else
      @status = NEW_STATUS
    end
  end

  def position_open?
    open_call_spread? || open_put_spread?
  end

  def position_closed?
    !position_open?
  end

  def open_put_spread?
    @put_positions.any? { |_, qty| qty != 0 }
  end

  def open_call_spread?
    @call_positions.any? { |_, qty| qty != 0 }
  end

  def update_open_positions
    trade_history.sort_by(&:timestamp).each do |event|
      case event[:event_type]
      when "OPEN_IRON_CONDOR"
        decrease_call_position(event[:call_short_leg_symbol], event[:quantity])
        increase_call_position(event[:call_long_leg_symbol], event[:quantity])
        decrease_put_position(event[:put_short_leg_symbol], event[:quantity])
        increase_put_position(event[:put_long_leg_symbol], event[:quantity])
      when "CLOSE_IRON_CONDOR"
        increase_call_position(event[:call_short_leg_symbol], event[:quantity])
        decrease_call_position(event[:call_long_leg_symbol], event[:quantity])
        increase_put_position(event[:put_short_leg_symbol], event[:quantity])
        decrease_put_position(event[:put_long_leg_symbol], event[:quantity])
      when "OPEN_PUT_SPREAD"
        decrease_put_position(event[:put_short_leg_symbol], event[:quantity])
        increase_put_position(event[:put_long_leg_symbol], event[:quantity])
      when "CLOSE_PUT_SPREAD"
        increase_put_position(event[:put_short_leg_symbol], event[:quantity])
        decrease_put_position(event[:put_long_leg_symbol], event[:quantity])
      when "OPEN_CALL_SPREAD"
        decrease_call_position(event[:call_short_leg_symbol], event[:quantity])
        increase_call_position(event[:call_long_leg_symbol], event[:quantity])
      when "CLOSE_CALL_SPREAD"
        increase_call_position(event[:call_short_leg_symbol], event[:quantity])
        decrease_call_position(event[:call_long_leg_symbol], event[:quantity])
      when "ADJUST_CALL_SPREAD"
        increase_call_spread(event[:close_short_leg_symbol], event[:quantity])
        decrease_call_spread(event[:close_long_leg_symbol], event[:quantity])
        decrease_call_spread(event[:open_short_leg_symbol], event[:quantity])
        increase_call_spread(event[:open_long_leg_symbol], event[:quantity])
      when "ADJUST_PUT_SPREAD"
        increase_put_spread(event[:close_short_leg_symbol], event[:quantity])
        decrease_put_spread(event[:close_long_leg_symbol], event[:quantity])
        decrease_put_spread(event[:open_short_leg_symbol], event[:quantity])
        increase_put_spread(event[:open_long_leg_symbol], event[:quantity])
      else
        raise "Unknown event type: #{event[:event_type]}"
      end
    end
  end

  def decrease_call_position(symbol, quantity_change)
    if @call_positions.has_key?(symbol)
      @call_positions[symbol] -= quantity_change
    else
      @call_positions[symbol] = -quantity_change
    end
  end

  def increase_call_position(symbol, quantity_change)
    if @call_positions.has_key?(symbol)
      @call_positions[symbol] += quantity_change
    else
      @call_positions[symbol] = quantity_change
    end
  end

  def decrease_put_position(symbol, quantity_change)
    if @put_positions.has_key?(symbol)
      @put_positions[symbol] -= quantity_change
    else
      @put_positions[symbol] = -quantity_change
    end
  end

  def increase_put_position(symbol, quantity_change)
    if @put_positions.has_key?(symbol)
      @put_positions[symbol] += quantity_change
    else
      @put_positions[symbol] = quantity_change
    end
  end

  def total_credit_debit
    @trade_history.reduce(0) { |sum, event| sum + (event[:credit_debit_amount] || 0) }
  end

  def open_price
    @trade_history.min_by { |event| event[:timestamp] }[:price]
  end

  def open_fees
    @trade_history.min_by { |event| event[:timestamp] }[:fees]
  end

  def open_commissions
    @trade_history.min_by { |event| event[:timestamp] }[:commissions]
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

  def update_history(kwargs)
    trade_event = kwargs.dup
    trade_event[:timestamp] = Time.now.utc.iso8601
    @trade_history << trade_event
  end

  def open?
    status == OPEN_STATUS
  end

  def closed?
    status == CLOSED_STATUS
  end

  def close_loss_price
    open_price * exit_loss_thresh
  end

  def max_loss_price
    round_down_to_nearest(open_price * exit_loss_thresh)
  end

  def break_even_price
    # this is per contract
    round_up_to_nearest((open_price * 100 + 2 * open_fees + 2 * open_commissions) / 100.0)
  end

  def target_profit_price
    # this is per contract
    round_down_to_nearest((open_price * 100 - open_fees - open_commissions) * exit_prof_thresh / 100.0)
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
      init_strategy: init_strategy,
      expiration_date: expiration_date,
      exit_prof_thresh: exit_prof_thresh,
      exit_loss_thresh: exit_loss_thresh,
      contracts: contracts,
      status: status,
      call_spread: call_spread.to_h,
      put_spread: put_spread.to_h,
      price_increment: price_increment,
      trade_history: trade_history.map(&:to_h),
      call_positions: @call_positions,
      put_positions: @put_positions
    }
  end

  private

  def trades_file_manager
    TradesFileManager.instance
  end
end
