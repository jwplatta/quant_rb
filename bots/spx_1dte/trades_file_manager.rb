require 'pry'
require 'date'
require 'fileutils'
require_relative 'iron_condor_trade'
require_relative 'data_objects'

class TradesFileManager
  def initialize(file_path)
    @file_path = file_path
    trades_dir = File.dirname(file_path)

    # Ensure the directory exists
    FileUtils.mkdir_p(trades_dir) unless Dir.exist?(trades_dir)

    # Create the file if it doesn't exist
    unless File.exist?(file_path)
      File.write(file_path, '{"trades": []}')
      @trades = []
    else
      @trades = read_trades
    end
  end

  attr_reader :trades

  def read_trades
    json_data = File.read(@file_path)
    data = JSON.parse(json_data, symbolize_names: true)
    @trades = data[:trades].map do |trade_data|
      trade_data = trade_data.transform_keys(&:to_sym)
    end
  end

  def reload
    @trades = read_trades
  end

  def open_trade?
    trades.any? { |trade| trade[:status] == 'OPEN' }
  end

  def get_open_trade
    trades = @trades.select { |trade| trade[:status] == 'OPEN' }
    if trades.count > 1
      raise "Multiple open trades found! Need to fix."
    else
      to_trade_object(trades.first)
    end
  end

  def update_trade(trade)
    trades.find { |t| t[:id] == trade.id }.then do |existing_trade|
      if existing_trade
        existing_trade.merge!(trade.to_h) # NOTE: I think this will update the trade in place
        write_trades(@trades)
      else
        raise "Trade with ID #{trade.id} not found!"
      end
    end
  end

  # NOTE: expects at trade object
  def save_trade(trade)
    raise "Trade with ID #{trade.id} already exists!" unless uniq_trade?(trade)

    @trades << trade.to_h
    write_trades(@trades)
  end

  def uniq_trade?(trade)
    !@trades.any? { |t| t[:id] == trade.id }
  end

  def write_trades(trades)
    data = { trades: trades.map(&:to_h) }
    File.write(@file_path, JSON.pretty_generate(data))
  end

  def to_trade_object(trade_data)
    expiration_date = if trade_data[:expiration_date].is_a?(String)
      Date.parse(trade_data[:expiration_date])
    end

    IronCondorTrade.new(
      id: trade_data[:id],
      put_spread: VerticalSpread.new(
        OptionLeg.new(**trade_data[:put_spread][:short_leg]),
        OptionLeg.new(**trade_data[:put_spread][:long_leg]),
        'PUT',
        trade_data[:put_spread][:contracts]
      ),
      call_spread: VerticalSpread.new(
        OptionLeg.new(**trade_data[:call_spread][:short_leg]),
        OptionLeg.new(**trade_data[:call_spread][:long_leg]),
        'CALL',
        trade_data[:call_spread][:contracts]
      ),
      open_price: trade_data[:open_price],
      open_fees: trade_data[:open_fees],
      open_commissions: trade_data[:open_commissions],
      close_price: trade_data[:close_price],
      close_fees: trade_data[:close_fees],
      close_commissions: trade_data[:close_commissions],
      total_credit_debit: trade_data[:total_credit_debit],
      total_fees: trade_data[:total_fees],
      total_commissions: trade_data[:total_commissions],
      exit_prof_thresh: trade_data[:exit_prof_thresh],
      exit_loss_thresh: trade_data[:exit_loss_thresh],
      contracts: trade_data[:contracts],
      status: trade_data[:status],
      price_increment: trade_data[:price_increment],
      adjustment_count: trade_data[:adjustment_count],
      expiration_date: expiration_date,
      trade_history: trade_data[:trade_history].map { |th| th.transform_keys(&:to_sym) }
    )
  end
end
