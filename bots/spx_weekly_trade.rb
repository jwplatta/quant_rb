require_relative '../services/search/call_spread_finder'
require_relative '../services/search/put_spread_finder'
require_relative '../services/trades/call_spread'
require_relative '../services/trades/put_spread'
require_relative '../services/trades/call_option'
require_relative '../services/trades/put_option'
require_relative '../mixins/schwab/schwab'

class SPXWeeklyTrade
  include Schwab

  TRADE_FILE = "../tmp/spx_weekly_trade.json"

  def initialize
    @underlying_symbol = '$SPX'
    @option_root = 'SPXW'
    @settlement_type = 'P' # PM settlement
  end

  attr_reader :underlying_symbol, :option_root, :settlement_type

  def run
  end

  def enter_trade
    exp_date = next_weekday
    opt_chain = option_chain(
      underlying_symbol,
      contract_type: 'CALL',
      from_date: exp_date,
      to_date: exp_date,
    )

    if opt_chain.nil?
      raise "No options chain found for #{underlying_symbol}"
    end

    new_trade = Services::Search::CallSpreadFinder.new(
      symbol: underlying_symbol,
      expiration_date: exp_date,
      short_delta: 0.08,
      max_spread: 25.0,
      min_credit: 105.0,
      min_open_interest: 0,
      dist_from_strike: 0.01,
      settlement_type: @settlement_type,
    ).search(opt_chain)

    if new_trade.is_a? Services::Trades::NullTrade
      puts "No suitable trade found for #{underlying_symbol}."
    else
      puts "Found trade: #{new_trade.short_leg.symbol} - #{new_trade.long_leg.symbol}"
      puts "Short leg strike: #{new_trade.short_leg.strike}, Long leg strike: #{new_trade.long_leg.strike}"
      puts "Credit: #{new_trade.credit}, Debit: #{new_trade.debit}"
      puts "Expiration date: #{new_trade.expiration_date}"

      new_trade.increment = 0.05
      new_trade.check_market

      new_trade.preview(order_instruction: :open)

      if new_trade.order_preview_status == 'ACCEPTED'
        # NOTE: if order preview is accepted, then open the trade
        puts "Order preview accepted. Opening trade..."
        new_trade.open

        while true
          if new_trade.filled?
            puts "Trade filled: #{new_trade.short_leg.symbol} - #{new_trade.long_leg.symbol}"
            puts "Order ID: #{new_trade.order_id}"
            puts "Order status: #{new_trade.order_status}"
            monitor_trade
          elsif new_trade.market_change?
            puts "Market conditions changed. Rechecking trade..."
            # NOTE: cancel order and try to enter trade again
            new_trade.cancel
            enter_trade
          elsif new_trade.working?
            puts "Order is still working. Status: #{new_trade.order_status}"
            sleep 5
          else
            puts "Order not filled yet. Status: #{new_trade.order_status}"
            puts "Waiting for 5 seconds before checking again..."
            sleep 5
          end
        end
      else
        puts "Order preview not accepted. Status: #{new_trade.order_preview_status}"
        puts "Rejects: #{new_trade.order_preview_rejects.join(', ')}"
        enter_trade
      end
    end
  ensure
    puts "Trade process completed."

    new_trade.cancel if new_trade
  end

  def monitor_trade
    while true
      puts "monitoring trade..."
      puts "Checking market conditions for #{underlying_symbol}..."
    end
  end

  def exit_trade
    short_leg_symbol = "SPXW  250613C06140000"
    long_leg_symbol = "SPXW  250613C06160000"
    quanity = 1

    short_leg = Services::Trades::CallOption.new(
      short_leg_symbol,
      quantity: quanity
    )
    long_leg = Services::Trades::CallOption.new(
      long_leg_symbol,
      quantity: quanity
    )

    call_spread = Services::Trades::CallSpread.new(
      short_leg: short_leg,
      long_leg: long_leg,
      quantity: quanity
    )
    call_spread.increment = 0.05
    call_spread.check_market
    r = call_spread.preview(order_instruction: :exit)
    puts r

    binding.pry
  end

  private

  def next_weekday
    date = Date.today + 7

    case date.wday
    when 0 # Sunday
      date + 1
    when 6 # Saturday
      date + 2
    else
      date
    end
  end
end


SPXWeeklyTrade.new.enter_trade
# SPXWeeklyTrade.new.exit_trade
