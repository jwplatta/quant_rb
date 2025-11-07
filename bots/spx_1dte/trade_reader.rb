require 'pry'
require 'date'
require 'fileutils'
require_relative 'iron_condor_trade'
require_relative 'data_objects'


class TradeReader
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

  def trades
  end

  def open_trade
  end
end
