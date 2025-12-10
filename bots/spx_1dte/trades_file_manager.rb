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

    Trade.new(
      id: trade_data[:id],
      status: trade_data[:status],
      exit_prof_price: trade_data[:exit_prof_price],
      exit_loss_mult: trade_data[:exit_loss_mult],
      price_increment: trade_data[:price_increment],
      trade_history: trade_history
    )
  end
end
