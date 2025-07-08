require 'fileutils'

module Platypi
  module Automation
    class Bot
      attr_reader :name, :mode, :account_name,
        :current_trade, :running, :config, :sleep_interval

      def initialize(name:, mode: :paper, account_name: nil, config: {})
        @name = name
        @mode = mode
        @account_name = account_name
        @config = config
        @running = false
        @current_trade = nil
        @sleep_interval = config[:sleep_interval] || 5
      end

      def clear_trade
        clear_current_trade_file
      end

      def start
        @running = true
        puts "Starting #{name} bot in #{mode} mode..."
        puts "Using Account: #{account_name}" if account_name

        try_restore_current_trade

        while @running
          begin
            if @current_trade
              handle_existing_trade
            else
              attempt_new_trade
            end

            sleep sleep_interval
          rescue => e
            handle_error(e)
          end
        end
      end

      def stop
        @running = false
        puts "Stopping #{name} bot..."
      end

      private

      def handle_existing_trade
        puts "Processing existing trade: #{@current_trade.trade_id}"

        @current_trade.next

        if @current_trade.exited?
          puts "Trade #{@current_trade.trade_id} completed"
          clear_current_trade_file
          @current_trade = nil
        end
      end

      def attempt_new_trade
        return unless should_enter_trade?

        puts "Looking for new trading opportunity..."

        @current_trade = create_new_trade
        write_current_trade_file

        puts "Created new trade: #{@current_trade.trade_id}"
      end

      def should_enter_trade?
        case @config[:enter_timing]
        when :immediately
          true
        when :last_trading_hour
          # TODO: Implement market hours logic
          puts "Last trading hour entry not implemented yet, defaulting to immediately"
          true
        when :opening
          # TODO: Implement market opening logic
          puts "Opening entry not implemented yet, defaulting to immediately"
          true
        else
          true
        end
      end

      def create_new_trade
        expiration_date = find_expiration_date

        Platypi::Trades::Trade.new(
          strategy_type: @config[:strategy_type],
          paper_trading: @mode == :paper,
          underlying_symbol: @config[:underlying_symbol],
          option_root: @config[:option_root],
          settlement_type: @config[:settlement_type],
          expiration_date: expiration_date,
          min_credit: @config[:min_credit],
          min_open_interest: @config[:min_open_interest],
          short_delta: @config[:max_delta],
          quantity: @config[:quantity] || 1,
          profit_thresh: @config[:profit_target_threshold] || 0.7,
          loss_thresh: @config[:max_loss_threshold] || -2.0,
          max_spread: @config[:max_spread] || 10.0,
          dist_from_strike: @config[:dist_from_strike] || 0.01,
          increment: @config[:increment] || 0.01
        )
      end

      def find_expiration_date
        days = @config[:days_to_expiration] || 1
        next_weekday(Date.today + days)
      end

      def next_weekday(date)
        case date.wday
        when 0 # Sunday
          date + 1
        when 6 # Saturday
          date + 2
        else
          date
        end
      end

      def write_current_trade_file
        File.write(current_trade_file_path, @current_trade.trade_id)
        puts "Wrote current trade ID to: #{current_trade_file_path}"
      end

      def clear_current_trade_file
        if File.exist?(current_trade_file_path)
          File.delete(current_trade_file_path)
          puts "Cleared current trade file: #{current_trade_file_path}"
        end
      end

      def current_trade_file_path
        File.join(bot_directory, "CURRENT_#{sanitized_bot_name}_TRADE.txt")
      end

      def sanitized_bot_name
        @name.upcase.gsub(/[^A-Z0-9]/, '_')
      end

      def bot_directory
        Dir.pwd
      end

      def current_trade_file_exists?
        File.exist?(current_trade_file_path)
      end

      def try_restore_current_trade
        trade_id = File.read(current_trade_file_path).strip

        unless trade_id.empty?
          puts "Found existing trade ID: #{trade_id}"
          trade = Platypi::Trades::Trade.load(trade_id)

          if trade
            @current_trade = trade
            puts "Restored existing trade: #{trade_id}"
          else
            puts "Trade #{trade_id} is no longer open, clearing file"
            clear_current_trade_file
          end
        end

      rescue => e
        puts "Error restoring trade: #{e.message}"
        clear_current_trade_file
      end

      def handle_error(e)
        puts "Error in bot loop: #{e.message}"
        puts e.backtrace.first(5) if @config[:debug]
        sleep(sleep_interval * 2)
      end
    end
  end
end
