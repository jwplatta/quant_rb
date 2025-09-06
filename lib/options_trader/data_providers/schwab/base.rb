module OptionsTrader
  module DataProviders
    module Schwab
      class Base
        class AuthenticationError < OptionsTrader::Error; end
        class RateLimitError < OptionsTrader::Error; end
        class NetworkError < OptionsTrader::Error; end
        class InvalidSymbolError < OptionsTrader::Error; end
        class ServiceUnavailableError < OptionsTrader::Error; end
        class TimeoutError < OptionsTrader::Error; end
        class InvalidParameterError < OptionsTrader::Error; end

        def initialize
          @client = OptionsTrader::DataProviders::Schwab::Client.instance
        end

        attr_reader :client

        private

        def handle_api_errors(operation_name = nil)
          yield
        rescue Net::HTTPError => e
          case e.response.code.to_i
          when 401, 403
            raise AuthenticationError, "Authentication failed for #{operation_name}: #{e.message}"
          when 429
            raise RateLimitError, "Rate limit exceeded for #{operation_name}: #{e.message}"
          when 400
            raise InvalidParameterError, "Invalid parameters for #{operation_name}: #{e.message}"
          when 404
            raise InvalidSymbolError, "Resource not found for #{operation_name}: #{e.message}"
          when 503, 502, 504
            raise ServiceUnavailableError, "Schwab service unavailable for #{operation_name}: #{e.message}"
          else
            raise NetworkError, "HTTP error for #{operation_name}: #{e.message}"
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise TimeoutError, "Request timeout for #{operation_name}: #{e.message}"
        rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
          raise NetworkError, "Network connection failed for #{operation_name}: #{e.message}"
        rescue JSON::ParserError => e
          raise NetworkError, "Invalid JSON response for #{operation_name}: #{e.message}"
        rescue StandardError => e
          # Re-raise OptionsTrader errors as-is
          raise if e.is_a?(OptionsTrader::Error)
          # Wrap other errors
          raise NetworkError, "Unexpected error for #{operation_name}: #{e.message}"
        end

        def validate_symbol(symbol)
          return if symbol.nil? || symbol.empty?

          unless unless symbol.match?(/^[\$A-Z0-9\/]+(\.[A-Z]{1,2})?$/)
            raise InvalidSymbolError, "Invalid symbol format: #{symbol}. Expected format: SYMBOL, $INDEX, or SYMBOL.EX"
          end
        end

        def log_operation(level, message, data = nil)
          return unless logger

          if data
            logger.send(level, "#{message}: #{data}")
          else
            logger.send(level, message)
          end
        end

        def logger
          OptionsTrader::Logger.instance
        end
      end
    end
  end
end
