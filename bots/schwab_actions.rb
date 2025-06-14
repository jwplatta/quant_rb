require_relative '../services/search/call_spread_finder'
require_relative '../services/search/put_spread_finder'
require_relative '../services/trades/call_spread'
require_relative '../services/trades/put_spread'
require_relative '../services/trades/call_option'
require_relative '../services/trades/put_option'
require_relative '../mixins/schwab/schwab'

class SchwabActions
  include Schwab

  def initialize
    @underlying_symbol = '$SPX'
    @option_root = 'SPXW'
  end

  attr_reader :underlying_symbol

  def enter_trade
    exp_date = next_weekday
    opt_chain = option_chain(
      underlying_symbol,
      contract_type: 'PUT',
      from_date: exp_date,
      to_date: exp_date
    )
    # opt_chain = option_chain(
    #   underlying_symbol,
    #   contract_type: 'CALL',
    #   days_to_expiration: 11
    # )

    if opt_chain.nil?
      raise "No options chain found for #{underlying_symbol}"
    end

    new_trade = Services::Search::PutSpreadFinder.new(
      symbol: underlying_symbol,
      expiration_date: exp_date,
      short_delta: 0.08,
      max_spread: 25.0,
      min_credit: 105.0,
      min_open_interest: 0,
      dist_from_strike: 0.01,
      option_root: @option_root,
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

      binding.pry

      # while true
      #   new_trade.check_market
      #   puts "Trade credit: #{new_trade.credit}"

      #   new_trade.preview(order_instruction: :open)
      #   puts "Order status: #{new_trade.order_preview_status}"

      #   puts "waiting..."
      #   sleep 5
      # end

      # r = new_trade.preview(order_instruction: :open)
      # puts r
      # binding.pry
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


SchwabActions.new.enter_trade
# SchwabActions.new.exit_trade
