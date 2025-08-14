# frozen_string_literal: true

require "mcp"
require "date"

module OptionsTrader
  module MCP
    module Tools
      class FindStrategy < ::MCP::Tool
        include Loggable

        description "Find options strategies (iron condors, vertical spreads, single options)"

        input_schema(
          properties: {
            strategy_type: {
              type: "string",
              description: "Type of option strategy to find",
              enum: OptionsTrader::Constants::VALID_STRATEGIES
            },
            contract_type: {
              type: "string",
              description: "Type of options to search for (e.g., 'CALL', 'PUT', 'ALL')",
              enum: %w[CALL PUT ALL],
              default: "ALL"
            },
            underlying_symbol: {
              type: "string",
              description: "Underlying symbol for the options (e.g., '$SPX', 'SPY')",
              pattern: "^[A-Za-z$]{1,6}$"
            },
            option_root: {
              type: "string",
              description: "Option root symbol (e.g., 'SPXW' for weekly SPX options)"
            },
            expiration_date: {
              type: "string",
              description: "Target expiration date for options (YYYY-MM-DD format)"
            },
            expiration_type: {
              type: "string",
              description: "Type of expiration (e.g., 'W' for weekly, 'S' for standard, 'NS' for non-standard, 'ALL' for all)",
              enum: %w[W S NS ALL],
              default: "W"
            },
            settlement_type: {
              type: "string",
              description: "Settlement type (e.g., 'P' for PM settled, 'A' for AM settled)",
              enum: %w[P A],
              default: "P"
            },
            max_delta: {
              type: "number",
              description: "Maximum absolute delta for short legs (default: 0.15)",
              minimum: 0.01,
              maximum: 1.0
            },
            max_spread: {
              type: "number",
              description: "Maximum spread width in dollars (default: 20.0)",
              minimum: 1.0
            },
            min_credit: {
              type: "number",
              description: "Minimum credit received in dollars (default: 100.0)",
              minimum: 0.01

            },
            min_open_interest: {
              type: "integer",
              description: "Minimum open interest for options (default: 0)",
              minimum: 0,
              default: 0
            },
            dist_from_strike: {
              type: "number",
              description: "Minimum distance from current price as percentage (default: 0.07)",
              minimum: 0.0,
              maximum: 1.0,
              default: 0.0
            },
            quantity: {
              type: "integer",
              description: "Number of contracts per leg (default: 1)",
              minimum: 1,
              default: 1
            },
            from_date: {
              type: "string",
              description: "Start date for expiration search (YYYY-MM-DD format)",
            },
            to_date: {
              type: "string",
              description: "End date for expiration search (YYYY-MM-DD format)",
            }
          },
          required: %w[strategy_type underlying_symbol option_root expiration_date]
        )

        annotations(
          title: "Find Options Strategy",
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true
        )

        def self.call(server_context:, strategy_type:, underlying_symbol:, option_root:, expiration_date:,
                      contract_type: "ALL", expiration_type: nil, settlement_type: nil,
                      max_delta: 0.15, max_spread: 20.0, min_credit: 0.0,
                      min_open_interest: 0, dist_from_strike: 0.0, quantity: 1,
                      from_date: nil, to_date: nil)
          logger.info("Finding #{strategy_type} strategy for #{underlying_symbol} expiring #{expiration_date}")

          begin
            unless OptionsTrader::Constants::VALID_STRATEGIES.include?(strategy_type.downcase)
              return ::MCP::Tool::Response.new([{
                                               type: "text",
                                               text: "**Error**: Invalid strategy type '#{strategy_type}'. Must be one of: #{OptionsTrader::Constants::VALID_STRATEGIES.join(', ')}."
                                             }])
            end

            exp_date = Date.parse(expiration_date)
            from_dt = from_date ? Date.parse(from_date) : exp_date
            to_dt = to_date ? Date.parse(to_date) : exp_date

            if (strategy_type == "vertical" || strategy_type == "single") && contract_type == "ALL"
              return ::MCP::Tool::Response.new([{
                                               type: "text",
                                               text: "**Error**: Contract type must be specified for vertical or single strategies."
                                             }])
            end

            logger.debug("Finding strategy with parameters: #{{
              strategy_type: strategy_type,
              underlying_symbol: underlying_symbol,
              expiration_date: exp_date,
              contract_type: contract_type,
              expiration_type: expiration_type,
              settlement_type: settlement_type,
              option_root: option_root,
              max_delta: max_delta,
              max_spread: max_spread,
              min_credit: min_credit,
              min_open_interest: min_open_interest,
              dist_from_strike: dist_from_strike,
              quantity: quantity,
              from_date: from_dt,
              to_date: to_dt
            }}")

            strategy = OptionsTrader::StrategySearchFactory.find(
              strategy_type: strategy_type,
              underlying_symbol: underlying_symbol,
              expiration_date: exp_date,
              put_call: contract_type,
              quantity: quantity,
              expiration_type: expiration_type,
              settlement_type: settlement_type,
              option_root: option_root,
              from_date: from_dt,
              to_date: to_dt,
              short_delta: max_delta,
              max_spread: max_spread,
              min_credit: min_credit,
              min_open_interest: min_open_interest,
              dist_from_strike: dist_from_strike,
              increment: 0.01
            )

            if strategy.nil?
              logger.info("No suitable #{strategy_type} found for #{underlying_symbol}")
              tool_response(
                "text",
                "**No Strategy Found**: Could not find a suitable #{strategy_type} for #{underlying_symbol} with the specified criteria."
              )
            else
              logger.info("Found #{strategy_type} strategy for #{underlying_symbol}")
              tool_response(
                "text",
                format_strategy_result(strategy, strategy_type)
              )
            end
          rescue Date::Error => e
            logger.error("Invalid date format: #{e.message}")
            tool_response("text", "**Error**: Invalid date format. Use YYYY-MM-DD format.")
          rescue StandardError => e
            logger.error("Error finding #{strategy_type} for #{underlying_symbol}: #{e.message}")
            logger.debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
            tool_response("text", "**Error** finding #{strategy_type} for #{underlying_symbol}: #{e.message}")
          end
        end

        def self.tool_response(type, text)
          ::MCP::Tool::Response.new([{
            type: type,
            text: text
          }])
        end

        def self.format_strategy_result(strategy, strategy_type)
          case strategy_type.downcase
          when "ironcondor"
            format_iron_condor(strategy)
          when "vertical"
            format_spread(strategy)
          else
            "**Found Strategy**: #{strategy_type.upcase}\n\n#{strategy.to_json}"
          end
        end

        def self.format_iron_condor(strategy)
          call_spread = strategy.call_spread
          put_spread = strategy.put_spread

          <<~TEXT
            **IRON CONDOR FOUND**

            **Underlying Symbol**: #{strategy.underlying_symbol}
            **Total Credit**: $#{(strategy.credit * 100).round(2)}
            **Spread Width**: $#{strategy.spread_width.round(2)}
            **Delta**: #{strategy.delta.round(4)}

            **Call Spread**:
            - Short: #{call_spread.short_leg.symbol} $#{call_spread.short_leg.strike} Call @ $#{call_spread.short_leg.mark.round(2)}
            - Long:  #{call_spread.long_leg.symbol} $#{call_spread.long_leg.strike} Call @ $#{call_spread.long_leg.mark.round(2)}
            - Credit: $#{(call_spread.credit * 100).round(2)}
            - Width: $#{call_spread.spread_width.round(2)}
            - Delta: #{call_spread.delta.round(4)}

            **Put Spread**:
            - Short: #{put_spread.short_leg.symbol} $#{put_spread.short_leg.strike} Put @ $#{put_spread.short_leg.mark.round(2)}
            - Long:  #{put_spread.long_leg.symbol} $#{put_spread.long_leg.strike} Put @ $#{put_spread.long_leg.mark.round(2)}
            - Credit: $#{(put_spread.credit * 100).round(2)}
            - Width: $#{put_spread.spread_width.round(2)}
            - Delta: #{put_spread.delta.round(4)}
          TEXT
        end

        def self.format_single
        end

        def self.format_spread(strategy)
          short_leg = strategy.short_leg
          long_leg = strategy.long_leg
          option_type = strategy.is_a?(OptionsTrader::CallSpread) ? "Call" : "Put"

          <<~TEXT
            **#{option_type.upcase} SPREAD FOUND**

            **Underlying Symbol**: #{strategy.underlying_symbol}
            **Credit**: $#{(strategy.credit * 100).round(2)}
            **Spread Width**: $#{strategy.spread_width.round(2)}
            **Delta**: #{strategy.delta.round(4)}

            **Short**: #{short_leg.symbol} $#{short_leg.strike} #{option_type} @ $#{short_leg.mark.round(2)}
            - Delta: #{short_leg.delta&.round(4)}
            - Open Interest: #{short_leg.open_interest}

            **Long**: #{long_leg.symbol} $#{long_leg.strike} #{option_type} @ $#{long_leg.mark.round(2)}
            - Delta: #{long_leg.delta&.round(4)}
            - Open Interest: #{long_leg.open_interest}
          TEXT
        end
      end
    end
  end
end