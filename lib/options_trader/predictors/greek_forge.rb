require 'net/http'
require 'uri'
require 'json'

module OptionsTrader
  module Predictors
    class GreekForge
      include OptionsTrader::Loggable

      class Error < OptionsTrader::Error; end
      class ConnectionError < Error; end
      class PredictionError < Error; end
      class TimeoutError < Error; end
      class InvalidResponseError < Error; end

      attr_reader :host, :port, :scheme

      def initialize(host: nil, port: nil, scheme: nil)
        @host = host || OptionsTrader.configuration.greek_forge_host
        @port = port || OptionsTrader.configuration.greek_forge_port
        @scheme = scheme || OptionsTrader.configuration.greek_forge_scheme
      end

      def health(params: {}, headers: {})
        uri = build_uri('/health', params)
        req = Net::HTTP::Get.new(uri)
        set_headers(req, headers)
        perform_request(uri, req)
      end

      def models(params: {}, headers: {})
        uri = build_uri('/models', params)
        req = Net::HTTP::Get.new(uri)
        set_headers(req, headers)
        perform_request(uri, req)
      end

      def model(contract_type, version, params: {}, headers: {})
        uri = build_uri("/models/#{contract_type}/#{version}", params)
        req = Net::HTTP::Get.new(uri)
        set_headers(req, headers)
        perform_request(uri, req)
      end

      def predict_delta(payload, params: {}, headers: {})
        uri = build_uri('/predict_delta', params)
        req = Net::HTTP::Post.new(uri)
        set_headers(req, headers)
        req.body = payload.to_json

        perform_request(uri, req)
      end

      def predict_deltas(payload, params: {}, headers: {})
        uri = build_uri('/predict_deltas', params)
        req = Net::HTTP::Post.new(uri)
        set_headers(req, headers)
        req.body = payload.to_json

        perform_request(uri, req)
      end

      private

      def build_uri(path, params = {})
        path = "/#{path}" unless path.start_with?('/')
        uri = URI::HTTP.build(scheme: @scheme, host: @host, port: @port, path: path)
        uri.query = URI.encode_www_form(params) unless params.nil? || params.empty?
        uri
      end

      def set_headers(req, headers)
        headers.each { |k, v| req[k] = v }
        req['Accept'] ||= 'application/json'
        req['Content-Type'] ||= 'application/json'
      end

      def perform_request(uri, req)
        logger.debug("GreekForge: HTTP #{req.method} #{uri}")

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 30) do |http|
          response = http.request(req)

          case response
          when Net::HTTPSuccess
            parse_body(response)
          when Net::HTTPServiceUnavailable
            msg = "GreekForge service unavailable: #{response.body}"
            logger.error(msg)
            raise ConnectionError, msg
          when Net::HTTPBadRequest, Net::HTTPUnprocessableEntity
            msg = "GreekForge prediction failed: #{response.body}"
            logger.error(msg)
            raise PredictionError, msg
          else
            msg = "GreekForge HTTP #{response.code} #{response.message}: #{response.body}"
            logger.error(msg)
            raise Error, msg
          end
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        msg = "GreekForge request timeout: #{e.message}"
        logger.error(msg)
        raise TimeoutError, msg
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        msg = "GreekForge connection failed (#{@host}:#{@port}): #{e.message}"
        logger.error(msg)
        raise ConnectionError, msg
      rescue JSON::ParserError => e
        msg = "GreekForge invalid JSON response: #{e.message}"
        logger.error(msg)
        raise InvalidResponseError, msg
      end

      def parse_body(response)
        content_type = response['Content-Type'].to_s
        if content_type.include?('application/json')
          JSON.parse(response.body)
        else
          response.body
        end
      rescue JSON::ParserError
        logger.warn('GreekForge: Failed to parse JSON response; returning raw body')
        response.body
      end
    end
  end
end
