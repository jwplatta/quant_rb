# frozen_string_literal: true

require "mcp"
require "mcp/server/transports/stdio_transport"
require_relative "tools/help"
require_relative "tools/find_strategy"

module OptionsTrader
  module MCP
    TOOLS = [
      Tools::Help,
      Tools::FindStrategy
    ].freeze

    class Server
      include Loggable

      def initialize
        configure_logging_for_mcp
        configure_mcp
        @server = ::MCP::Server.new(
          name: "options_trader_mcp_server",
          version: OptionsTrader::VERSION,
          tools: TOOLS,
        )
      end

      def start
        logger.info("Starting OptionsTrader MCP Server #{OptionsTrader::VERSION}")
        logger.info("Available tools: #{TOOLS.map { |tool| tool.name.split('::').last }.join(', ')}")
        logger.info("Logs will be written to: #{log_file_path}")
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      private

      def configure_logging_for_mcp
        OptionsTrader.configure do |config|
          config.log_file = log_file_path
          config.log_to_stdout = false
          config.log_level = :debug
        end
      end

      def log_file_path
        @log_file_path ||= ENV['LOGFILE'] || '/tmp/options_trader_mcp.log'
      end

      def configure_mcp
        ::MCP.configure do |config|
          config.exception_reporter = ->(exception, server_context) do
            logger.error("MCP Error: #{exception.class.name} - #{exception.message}")
            logger.debug(exception.backtrace.first(3).join("\n"))
          end

          config.instrumentation_callback = ->(data) do
            duration = data[:duration] ? " - #{data[:duration].round(3)}s" : ""
            logger.info("MCP: #{data[:method]}#{data[:tool_name] ? " (#{data[:tool_name]})" : ""}#{duration}")
            logger.debug(data.inspect)
          end
        end
      end
    end
  end
end
