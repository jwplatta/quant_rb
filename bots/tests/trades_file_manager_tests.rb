require 'pry'
require 'fileutils'

require_relative '../spx_1dte/trades_file_manager'
require_relative '../spx_1dte/iron_condor_trade'

TradesFileManager.setup('bots/tests/fixtures/test_trades.json')
tf_manager = TradesFileManager.instance

### TEST #trades ###
raise "Expected 0 trades, got #{tf_manager.trades.length}" unless tf_manager.trades.length == 0

### TEST #reload ###
### TEST #read_all ###
TradesFileManager.setup('bots/tests/fixtures/open_trade_example.json')
tf_manager.reload

raise "Expected 3 trades, got #{tf_manager.trades.length}" unless tf_manager.trades.length == 3

### TEST #open_trade ###
raise "Wrong open trade ID: '#{tf_manager.open_trade.id}'" unless tf_manager.open_trade.id == '1f7454492f8b4bf2b1687f4b8bb3b6ea'

### TEST #open_trade? ###
raise "Expected open_trade? to be true" unless tf_manager.open_trade?

open_trade = tf_manager.open_trade

TradesFileManager.setup('bots/tests/fixtures/all_closed_trades_example.json')
tf_manager.reload

raise "Expected 2 trades, got #{tf_manager.trades.length}" unless tf_manager.trades.length == 2
raise "Expected open_trade? to be false" if tf_manager.open_trade?

### TEST #create ###
test_file = 'bots/tests/fixtures/test_trades.json'
TradesFileManager.setup(test_file)
tf_manager.reload
tf_manager.create(open_trade)
raise "Expected 1 trades, got #{tf_manager.trades.length}" unless tf_manager.trades.length == 1

### TEST #update ###
trade = tf_manager.open_trade
trade.instance_variable_set(:@status, 'CLOSED')

tf_manager.update(trade)
updated_trade = tf_manager.trades.find { |t| t.id == trade.id }
raise "Trade status not updated!" unless updated_trade.status == 'CLOSED'

### TEST #delete ###
tf_manager.delete(trade.id)
raise "Expected 0 trades after delete, got #{tf_manager.trades.length}" unless tf_manager.trades.length == 0

### CLEANUP TEST FILE ###
FileUtils.rm_f(test_file)
puts "Deleted #{test_file}" unless File.exist?(test_file)
