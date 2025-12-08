require 'pry'
require 'date'
require 'fileutils'
require_relative 'trade'
require_relative 'data_objects'
require 'singleton'

class TradesFileManager
  include Singleton

  def self.setup(file_path)
    instance.file_path = file_path

    trades_dir = File.dirname(file_path)

    FileUtils.mkdir_p(trades_dir) unless Dir.exist?(trades_dir)

    unless File.exist?(file_path)
      File.write(file_path, '{"trades": []}')
    end
  end

  def initialize
    @trades = nil
  end

  attr_accessor :file_path

  def trades
    return @trades unless @trades.nil?

    @trades = read_all
  end

  def open_trade
    open_trades = trades.select { |trade| trade.status == Trade::OPEN_STATUS }
    if open_trades.count > 1
      raise "Multiple open trades found! Need to fix."
    elsif open_trades.empty?
      nil
    else
      open_trades.first
    end
  end

  def reload
    @trades = nil
    trades
  end

  def open_trade?
    trades.any? { |trade| trade.status == 'OPEN' }
  end

  def read_all
    json_data = File.read(file_path)
    data = JSON.parse(json_data, symbolize_names: true)

    @trades = data[:trades].map do |trade_data|
      to_trade_object(trade_data)
    end
  rescue JSON::ParserError => e
    @trades = []
  end

  def update(trade)
    new_trades = trades.reject { |t| t.id == trade.id }
    new_trades << trade
    @trades = new_trades
    write_trades(@trades)
  end

  def create(new_trade)
    raise ArgumentError, "trade must respond to :to_h" unless new_trade.respond_to?(:to_h)

    trades # ensure @trades is loaded

    exists = @trades.any? do |t|
      if t.respond_to?(:id)
        t.id == new_trade.id
      elsif t.is_a?(Hash)
        t[:id] == new_trade.id
      else
        false
      end
    end

    raise "Trade with ID #{new_trade.id} already exists!" if exists

    @trades << new_trade

    write_trades(@trades)
  end

  def delete(trade_id)
    trades = @trades.reject { |trade| trade.id == trade_id }
    if trades.length == @trades.length
      raise "Trade with ID #{trade_id} not found!"
    end
    @trades = trades
    write_trades(@trades)
  end

  def write_trades(trades)
    data = { trades: trades.map(&:to_h) }
    File.write(file_path, JSON.pretty_generate(data))
  end

  def to_trade_object(trade_data)
    # Parse trade history events
    trade_history = if trade_data[:trade_history]
      trade_data[:trade_history].map do |e|
        e.merge({
          timestamp: Time.parse(e[:timestamp]),
          credit_debit_type: e[:credit_debit_type]&.to_sym
        })
      end
    else
      []
    end

    # Reconstruct init_strategy from trade history or stored data
    init_strategy = if trade_data[:call_spread] && trade_data[:put_spread]
      build_iron_condor_strategy(trade_data)
    else
      nil
    end

    Trade.new(
      id: trade_data[:id],
      init_strategy: init_strategy,
      status: trade_data[:status],
      exit_prof_thresh: trade_data[:exit_prof_thresh],
      exit_loss_thresh: trade_data[:exit_loss_thresh],
      price_increment: trade_data[:price_increment],
      trade_history: trade_history
    )
  end

  private

  def build_iron_condor_strategy(trade_data)
    call_spread = build_vertical_spread(trade_data[:call_spread], 'CALL')
    put_spread = build_vertical_spread(trade_data[:put_spread], 'PUT')

    expiration_date = if trade_data[:expiration_date].is_a?(String)
      Date.parse(trade_data[:expiration_date])
    else
      trade_data[:expiration_date]
    end

    IronCondor.new(
      put_spread: put_spread,
      call_spread: call_spread,
      quantity: trade_data[:contracts] || 1,
      expiration_date: expiration_date,
      price_increment: trade_data[:price_increment] || 0.05
    )
  end

  def build_vertical_spread(spread_data, contract_type)
    short_leg = build_option_leg(spread_data[:short_leg], contract_type)
    long_leg = build_option_leg(spread_data[:long_leg], contract_type)

    VerticalSpread.new(
      short_leg: short_leg,
      long_leg: long_leg,
      contract_type: contract_type,
      quantity: spread_data[:contracts] || 1,
      expiration_date: Date.parse(spread_data[:short_leg][:expiration_date])
    )
  end

  def build_option_leg(leg_data, contract_type)
    expiration_date = if leg_data[:expiration_date].is_a?(String)
      Date.parse(leg_data[:expiration_date])
    else
      leg_data[:expiration_date]
    end

    OptionLeg.new(
      symbol: leg_data[:symbol],
      contract_type: contract_type,
      strike: leg_data[:strike],
      mark: leg_data[:mark],
      delta: leg_data[:delta],
      expiration_date: expiration_date,
      quantity: 1
    )
  end
end
