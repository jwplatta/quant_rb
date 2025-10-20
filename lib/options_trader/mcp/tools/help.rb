# frozen_string_literal: true

require "mcp"

module OptionsTrader
  module MCP
    module Tools
      class Help < ::MCP::Tool
        include Loggable

        description "Get comprehensive help and documentation for the OptionsTrader system and capabilities"

        input_schema(
          properties: {
            topic: {
              type: "string",
              description: "Optional specific topic to get help for. Available: 'trading', 'bots', 'strategies', 'setup'",
              enum: ["trading", "bots", "strategies", "setup"]
            }
          },
          required: []
        )

        annotations(
          title: "Get Help and Documentation",
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true
        )

        def self.call(topic: nil, server_context:)

          logger.debug("Help tool called with topic: #{topic.inspect}")

          help_content = if topic
            get_topic_help(topic)
          else
            get_general_help
          end

          ::MCP::Tool::Response.new([{
            type: "text",
            text: help_content
          }])
        end

        private

        def self.get_general_help
          <<~HELP
            # 🤖 Options Trader MCP Server

            MCP (Model Context Protocol) server for the Options Trader system, providing AI agents with tools to find and analyze options trading strategies.

            ## Available Tools:

            ### 1. Help Tool
            Get comprehensive documentation and guidance for the Options Trader system.
            - **Description**: Access help topics and system documentation
            - **Usage**: Use with optional topic parameter for specific help sections
            - **Topics**: 'trading', 'bots', 'strategies', 'setup'

            ### 2. Find Strategy Tool
            Find options strategies using sophisticated search criteria.
            - **Description**: Discover iron condors, vertical spreads, and single options
            - **Strategy Types**: iron condor, vertical spreads (call/put), single options
            - **Parameters**: underlying symbol, expiration dates, delta/credit filters, open interest
            - **Output**: Formatted strategy details with pricing and risk metrics

            ## Tool Usage Examples:

            ### Get Help
            ```
            help_tool()                          # General system overview
            help_tool(topic: "strategies")       # Strategy-specific help
            help_tool(topic: "setup")           # Installation and configuration
            ```

            ### Find Strategies
            ```
            # Find SPX iron condor expiring January 31st
            find_strategy_tool(
              strategy_type: "ironcondor",
              underlying_symbol: "$SPX",
              option_root: "SPXW",
              expiration_date: "2025-01-31",
              min_credit: 100.0,
              max_delta: 0.15
            )

            # Find SPY call spread
            find_strategy_tool(
              strategy_type: "vertical",
              contract_type: "CALL",
              underlying_symbol: "SPY",
              option_root: "SPY",
              expiration_date: "2025-02-07",
              min_credit: 50.0
            )
            ```

            ## Quick Reference:
            - Use `help_tool(topic: "setup")` for installation and configuration
            - Use `help_tool(topic: "strategies")` for available strategy types and parameters
            - Use `find_strategy_tool()` to discover trading opportunities with your criteria

            The MCP server provides AI agents with access to the full Options Trader system's strategy discovery capabilities through these two focused tools.
          HELP
        end

        def self.get_topic_help(topic)
          case topic
          when "trading"
            get_trading_help
          when "bots"
            get_bots_help
          when "strategies"
            get_strategies_help
          when "setup"
            get_setup_help
          else
            "**Error**: Unknown topic '#{topic}'. Available topics: trading, bots, strategies, setup"
          end
        end

        def self.get_trading_help
          <<~HELP
            # 📊 Manual Trading

            ## Strategy Finders

            ### IronCondorFinder
            Find iron condor opportunities with sophisticated filtering.
            ```ruby
            finder = OptionsTrader::Search::IronCondorFinder.new
            strategies = finder.find_strategies(
              underlying_symbol: '$SPX',
              expiration_date: '2025-01-31',
              min_credit: 100.0,        # Minimum net credit
              max_delta: 0.15,          # Maximum delta for short legs
              max_spread: 25.0,         # Maximum spread width
              min_open_interest: 10,    # Minimum open interest
              dist_from_strike: 0.07    # Distance from current price
            )
            ```

            ### CallSpreadFinder / PutSpreadFinder
            Find vertical spread opportunities.
            ```ruby
            call_finder = OptionsTrader::Search::CallSpreadFinder.new
            put_finder = OptionsTrader::Search::PutSpreadFinder.new

            call_spreads = call_finder.find_strategies(
              underlying_symbol: 'SPY',
              expiration_date: '2025-02-07',
              min_credit: 50.0,
              max_delta: 0.30
            )
            ```

            ## Order Management

            ### Order Factory
            Construct complex orders programmatically.
            ```ruby
            factory = OptionsTrader::Schwab::Orders::OrderFactory.new

            # Iron condor order
            order = factory.create_iron_condor_order(
              strategy: iron_condor_strategy,
              quantity: 1,
              price: 1.50,
              instruction: 'SELL_TO_OPEN'
            )

            # Vertical spread order
            order = factory.create_vertical_order(
              strategy: call_spread_strategy,
              quantity: 2,
              price: 0.75,
              instruction: 'SELL_TO_OPEN'
            )
            ```

            ### Trade Execution
            Execute trades with full lifecycle management.
            ```ruby
            # Create and enter trade
            trade = OptionsTrader::Trades::Trade.new(strategy: strategy)
            trade.enter_trade!

            # Monitor trade progress
            trade.check_exit_conditions!

            # Manual exit
            trade.exit_trade!
            ```

            ## Market Data

            ### Quote Data
            Get real-time quotes for analysis.
            ```ruby
            schwab = OptionsTrader::Schwab::Schwab.new
            quote = schwab.quote('$SPX')
            quotes = schwab.quotes(['SPY', 'AAPL', 'TSLA'])
            ```

            ### Option Chain Analysis
            Process complete option chains.
            ```ruby
            option_chain = schwab.option_chain('SPX')
            # Access calls, puts, and underlying data
            calls = option_chain.call_exp_date_map
            puts = option_chain.put_exp_date_map
            underlying = option_chain.underlying
            ```
          HELP
        end

        def self.get_bots_help
          <<~HELP
            # 🤖 Trading Bots

            ## Bot DSL Configuration

            ### Basic Bot Setup
            ```ruby
            bot = OptionsTrader.create_bot do
              set_name 'My Trading Bot'
              set_mode :paper              # :paper or :live
              set_account_name 'TRADING_BROKERAGE_ACCOUNT'
              set_interval 300             # Check interval in seconds
            end
            ```

            ### Strategy Configuration
            ```ruby
            # Iron Condor Bot
            bot = OptionsTrader.create_bot do
              set_name 'SPX Weekly Iron Condor'
              set_mode :paper

              use_strategy 'ironcondor' do
                set_underlying_symbol '$SPX'
                set_option_root 'SPXW'
                set_settlement_type 'PM'
                set_days_to_expiration 1
                set_min_credit 100
                set_max_delta 0.15
                set_max_spread 25
                set_min_open_interest 10
                set_dist_from_strike 0.07
                set_quantity 1
              end

              exit_when do
                profit_target_threshold 0.7    # Exit at 70% profit
                max_loss_threshold 2.5         # Exit at 250% loss
              end
            end
            ```

            ### Entry Timing
            ```ruby
            # Time-based entry
            enter_trade_when :market_open
            enter_trade_when :market_close
            enter_trade_when time: '09:30'

            # Condition-based entry (future feature)
            enter_trade_when do
              vix.below 20
              market.trending_up
              time.after '10:00'
            end
            ```

            ## Bot Execution

            ### Running Bots
            ```ruby
            # Start bot (runs continuously)
            bot.start!

            # Run single iteration
            bot.run_once!

            # Stop bot
            bot.stop!
            ```

            ### Bot States
            - `INITIALIZED`: Created but not started
            - `SEARCHING`: Looking for trade opportunities
            - `ORDER_PENDING`: Order submitted, waiting for fill
            - `POSITION_ACTIVE`: Trade entered, monitoring
            - `EXITING`: Exit order submitted
            - `COMPLETED`: Trade closed

            ## Configuration Options

            ### Strategy Types
            - `'ironcondor'`: Iron condor spreads
            - `'callspread'`: Bull call spreads
            - `'putspread'`: Bear put spreads

            ### Trading Modes
            - `:paper`: Simulation mode (no real orders)
            - `:live`: Real money trading

            ### Exit Conditions
            - `profit_target_threshold`: Exit at profit percentage
            - `max_loss_threshold`: Stop loss percentage
            - `days_to_expiration`: Exit before expiration
            - `time_based`: Exit at specific time

            ## Example Bot Files
            See `spx_1DTE_bot.rb` for a complete working example.
          HELP
        end

        def self.get_strategies_help
          <<~HELP
            # 📈 Trading Strategies

            ## Available Strategies

            ### Iron Condor
            Short both call and put spreads for neutral income.
            ```ruby
            # Strategy object
            iron_condor = OptionsTrader::Strategies::IronCondor.new(
              put_short_symbol: 'SPX250131P05900000',
              put_long_symbol: 'SPX250131P05875000',
              call_short_symbol: 'SPX250131C06100000',
              call_long_symbol: 'SPX250131C06125000'
            )

            # Key properties
            iron_condor.type              # 'ironcondor'
            iron_condor.put_spread        # Put spread component
            iron_condor.call_spread       # Call spread component
            iron_condor.max_profit        # Maximum profit potential
            iron_condor.max_loss          # Maximum loss potential
            iron_condor.breakeven_points  # [lower, upper] breakeven
            ```

            ### Call Spread (Bull Call / Bear Call)
            ```ruby
            call_spread = OptionsTrader::Strategies::CallSpread.new(
              short_symbol: 'SPY250207C00610000',
              long_symbol: 'SPY250207C00615000'
            )

            # Properties
            call_spread.spread_width      # Width in dollars
            call_spread.net_credit        # Credit received (bear call)
            call_spread.net_debit         # Debit paid (bull call)
            ```

            ### Put Spread (Bull Put / Bear Put)
            ```ruby
            put_spread = OptionsTrader::Strategies::PutSpread.new(
              short_symbol: 'SPY250207P00590000',
              long_symbol: 'SPY250207P00585000'
            )
            ```

            ### Individual Options
            ```ruby
            call_option = OptionsTrader::Strategies::CallOption.new(
              symbol: 'AAPL250221C00180000'
            )

            put_option = OptionsTrader::Strategies::PutOption.new(
              symbol: 'AAPL250221P00170000'
            )
            ```

            ## Strategy Properties

            ### Common Methods
            All strategies implement:
            - `type`: Strategy type string
            - `to_h`: Serialize to hash
            - `from_h(hash)`: Deserialize from hash
            - `symbols`: Array of option symbols involved
            - `legs`: Array of individual option legs

            ### Risk Metrics
            - `max_profit`: Maximum profit potential
            - `max_loss`: Maximum loss potential
            - `breakeven_points`: Breakeven price levels
            - `profit_loss_at(price)`: P&L at specific price

            ## Strategy Discovery

            ### Search Parameters
            Common search filters across all finders:
            - `underlying_symbol`: '$SPX', 'SPY', etc.
            - `expiration_date`: Target expiration 'YYYY-MM-DD'
            - `min_credit`: Minimum credit received
            - `max_delta`: Maximum delta for short legs
            - `max_spread`: Maximum spread width
            - `min_open_interest`: Minimum open interest filter
            - `dist_from_strike`: Distance from current price
            - `settlement_type`: 'AM' or 'PM' settlement
            - `option_root`: Specific option root (e.g., 'SPXW')

            ### Factory Pattern
            ```ruby
            # Get appropriate finder for strategy type
            finder = OptionsTrader::Search::StrategyFinderFactory.create('ironcondor')
            strategies = finder.find_strategies(search_params)
            ```

            ## Data Objects Integration
            All strategies work with schwab_rb data objects:
            - `DataObjects::OptionContract`: Individual option details
            - `DataObjects::OptionChain`: Complete option chain
            - `DataObjects::Quote`: Real-time quote data
            - `DataObjects::Order`: Order specifications
          HELP
        end

        def self.get_setup_help
          <<~HELP
            # 🚀 Setup Guide

            ## 1. Prerequisites
            - Ruby 3.2.2 or later
            - Schwab brokerage account
            - Approved Schwab developer account (developer.schwab.com)
            - SQLite3 (for trade persistence)

            ## 2. Installation
            ```bash
            git clone <repository>
            cd options_trader
            bundle install
            rake db:init
            ```

            ## 3. Environment Configuration
            Create `.env` file with required variables:
            ```bash
            # Schwab API Configuration
            SCHWAB_API_KEY="your_app_key"
            SCHWAB_APP_SECRET="your_app_secret"
            SCHWAB_CALLBACK_URI="https://localhost:8443/callback"
            SCHWAB_TOKEN_PATH="./schwab_token.json"

            # Account Configuration
            TRADING_BROKERAGE_ACCOUNT="your_account_number"
            IRA_ACCOUNT="your_ira_account_number"

            # Optional Configuration
            LOG_LEVEL="INFO"
            LOGFILE="./tmp/schwab.log"
            ```

            ## 4. Authentication Setup
            Initial OAuth2 authentication with Schwab:
            ```bash
            # This opens browser for Schwab login
            bundle exec exe/schwab_token_refresh
            ```

            ## 5. Database Setup
            ```bash
            rake db:init       # Create database
            rake db:migrate    # Run migrations
            rake db:reset      # Reset if needed
            ```

            ## 6. Verify Installation
            ```bash
            # Run tests
            bundle exec rspec

            # Test Schwab connection
            ruby -r ./lib/options_trader -e "puts OptionsTrader::Schwab::Schwab.new.quote('$SPX')"
            ```

            ## 7. Configuration Files

            ### Database Config (`config/database.yml`)
            ```yaml
            development:
              adapter: sqlite3
              database: db/development.sqlite3
              pool: 5
              timeout: 5000
            ```

            ### Environment Config (`config/environment.rb`)
            Central configuration and requires.

            ## 8. Account Setup
            Configure account mappings in environment:
            ```bash
            # Format: ACCOUNT_NAME_ACCOUNT="schwab_account_number"
            export TRADING_BROKERAGE_ACCOUNT="12345678"
            export RETIREMENT_IRA_ACCOUNT="87654321"
            ```

            ## 9. Paper Trading Setup
            Start with paper trading to test configuration:
            ```ruby
            bot = OptionsTrader.create_bot do
              set_name 'Test Bot'
              set_mode :paper  # Safe simulation mode
              # ... rest of configuration
            end
            ```

            ## 10. MCP Server (Optional)
            Start the MCP server for AI integration:
            ```bash
            bundle exec exe/options_trader_mcp
            # Or use the shell script
            ./start_mcp_server.sh
            ```

            ## Troubleshooting

            ### Common Issues
            - **Token expiration**: Run `bundle exec exe/schwab_token_refresh`
            - **Database errors**: Run `rake db:reset`
            - **Missing dependencies**: Run `bundle install`
            - **Permission errors**: Check file permissions on token file

            ### Logging
            - Default log location: `./tmp/schwab.log`
            - Adjust log level via `LOG_LEVEL` environment variable
            - Use `LOG_LEVEL=DEBUG` for detailed API interaction logs

            ### Testing
            - Run all tests: `bundle exec rspec`
            - Run specific test: `bundle exec rspec spec/path/to/test_spec.rb`
            - Focus on failing tests: `bundle exec rspec --only-failures`

            ## Directory Structure
            ```
            lib/options_trader/
            ├── automation/          # Bot framework
            ├── charts/             # Visualization
            ├── mcp/               # MCP server tools
            ├── schwab/            # Schwab API integration
            ├── search/            # Strategy finders
            ├── strategies/        # Trading strategies
            └── trades/            # Trade management
            ```
          HELP
        end
      end
    end
  end
end