module OptionsTrader
  class SPXWeekly
    def initialize(mode: :preview)
      @mode = mode
      @underlying_symbol = '$SPX'
      @option_root = 'SPXW'
      @settlement_type = 'P' # NOTE: PM settlement
      @sleep_interval = 10 # seconds between monitoring checks
      @running = false
    end

    attr_reader :underlying_symbol, :option_root, :settlement_type, :mode, :sleep_interval

    def run
      puts "Starting SPX Weekly bot in #{mode} mode..."
      @running = true

      while @running
        begin
          current_trade = find_current_trade

          if current_trade
            puts "Found existing trade: #{current_trade.trade_id}"
            puts "Trade status: #{current_trade.status}"
            handle_existing_trade(current_trade)
          else
            puts "No current trade found. Looking for new opportunity..."
            attempt_new_trade
          end

        rescue => e
          puts "Error in main loop: #{e.message}"
          puts "Retrying in #{sleep_interval} seconds..."
          sleep sleep_interval
        end
      end
    end

    def stop
      puts "Stopping SPX Weekly bot..."
      @running = false
    end

    private

    def find_current_trade
      open_trades = OptionsTrader::Trades::Trade.find_open_trades
      open_trades.first
    end

    def handle_existing_trade(trade)
      case trade.status
      when 'OPEN', 'PREVIEW_OPEN'
        if trade.filled? || trade.preview
          monitor_trade_until_exit(trade)
        else
          wait_for_order_completion(trade)
        end
      when 'EXIT', 'PREVIEW_EXIT'
        if trade.filled? || trade.preview
          complete_trade(trade)
        else
          wait_for_order_completion(trade)
        end
      else
        puts "Unknown trade status: #{trade.status}"
        sleep sleep_interval
      end
    end

    def attempt_new_trade
      strategy = find_trading_opportunity
      return sleep(sleep_interval) unless strategy

      trade = create_trade(strategy)
      return sleep(sleep_interval) unless trade

      if place_opening_order(trade)
        puts "Order placed successfully"
      else
        puts "Failed to place order, will retry..."
        sleep sleep_interval
      end
    end

    def find_trading_opportunity
      exp_date = next_weekday
      puts "Looking for opportunities expiring: #{exp_date}"

      finder = OptionsTrader::IronCondorFinder.new(
        underlying_symbol: underlying_symbol,
        expiration_date: exp_date,
        short_delta: 0.08,
        max_spread: 25.0,
        min_credit: 105.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        settlement_type: settlement_type,
        option_root: option_root
      )

      strategy = finder.search(
        from_date: exp_date,
        to_date: exp_date
      )

      if strategy.is_a?(OptionsTrader::NullStrategy)
        puts "No suitable trades found"
        return nil
      end

      puts "Found iron condor strategy:"
      puts "  Call spread: #{strategy.call_spread.short_leg.strike}/#{strategy.call_spread.long_leg.strike}"
      puts "  Put spread: #{strategy.put_spread.short_leg.strike}/#{strategy.put_spread.long_leg.strike}"
      puts "  Total credit: #{strategy.credit}"

      strategy
    end

    def create_trade(strategy)
      strategy.increment = 0.05
      strategy.check_market

      OptionsTrader::Trades::Trade.new(
        strategy: strategy,
        preview: (mode == :preview)
      )
    rescue => e
      puts "Error creating trade: #{e.message}"
      nil
    end

    def place_opening_order(trade)
      trade.open

      if trade.preview
        if trade.accepted?
          puts "Preview order accepted"
          true
        else
          puts "Preview order rejected: #{trade.order_rejects.join(', ')}"
          false
        end
      else
        puts "Live order placed with ID: #{trade.order_id}"
        true
      end
    rescue => e
      puts "Error placing order: #{e.message}"
      false
    end

    def wait_for_order_completion(trade)
      return if trade.preview # Preview orders don't need to wait for fill

      max_wait_time = 300 # 5 minutes
      start_time = Time.now
      order_type = trade.opening? ? "entry" : "exit"

      while Time.now - start_time < max_wait_time
        trade.check_order_status

        if trade.filled?
          puts "#{order_type.capitalize} order filled! ID: #{trade.order_id}"
          return
        elsif trade.working?
          puts "#{order_type.capitalize} order working... Status: #{trade.order_status}"
          sleep 10
        elsif trade.opening? && trade.strategy.market_change?
          puts "Market conditions changed. Canceling order..."
          trade.stop_order
          return
        else
          puts "#{order_type.capitalize} order status: #{trade.order_status}"
          sleep 5
        end
      end

      # Timeout reached
      puts "Order timeout reached"
      if trade.opening?
        puts "Canceling entry order and will retry..."
        trade.stop_order
      else
        puts "Exit order timeout - manual intervention may be needed"
      end
    end

    def monitor_trade_until_exit(trade)
      puts "Monitoring trade: #{trade.trade_id}"

      # Single monitoring check, not a loop
      progress = trade.check_progress
      risk = trade.check_risk

      puts "Trade progress: #{progress&.round(2)}%, Risk status: #{risk}"

      if progress.nil?
        puts "Cannot calculate progress, will check again next cycle"
        sleep sleep_interval
        return
      end

      progress = progress.round(2)

      if progress >= 100.0
        puts "Profit target reached (#{progress}%)"
        place_exit_order(trade)
      elsif progress <= -100.0
        puts "Stop loss triggered (#{progress}%)"
        place_exit_order(trade)
      elsif risk == 'YELLOW'
      elsif risk == 'RED'
        puts "HIGH RISK DETECTED! Delta breach - manual intervention required"
        @running = false # Stop the bot for manual review
      else
        puts "\nContinuing to monitor...\n"
        sleep sleep_interval
      end
    end

    def place_exit_order(trade)
      puts "Placing exit order for trade: #{trade.trade_id}"

      trade.strategy.check_market
      trade.strategy.increment = 0.05
      trade.exit

      if trade.preview
        puts "Preview exit order created"
      else
        puts "Exit order placed"
      end
    rescue => e
      puts "Error placing exit order: #{e.message}"
    end

    def complete_trade(trade)
      puts "Trade #{trade.trade_id} completed successfully"
      puts "Looking for next opportunity in #{sleep_interval} seconds..."
      sleep sleep_interval
    end

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
end
