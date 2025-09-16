require "json"
require "net/http"
require "uri"
require "aws-sdk-s3"

module OptionsTrader
  module DataProviders
    module Polygon
      class Client
        BASE_URL = 'https://api.polygon.io'

        def initialize(api_key = nil)
          @api_key = api_key || ENV['POLYGON_OPTIONS_API_KEY']
          @aws_access_key_id = ENV['POLYGON_AWS_ACCESS_KEY_ID']
          @aws_secret_access_key = ENV['POLYGON_AWS_SECRET_ACCESS_KEY']
          
          raise ArgumentError, "API key is required" if @api_key.nil? || @api_key.empty?
          raise ArgumentError, "AWS credentials are required for file downloads" if @aws_access_key_id.nil? || @aws_secret_access_key.nil?
        end

        # us_options_opra/day_aggs_v1
        def get_day_aggs(date, local_file_path = nil)
          date_obj = Date.parse(date.to_s)
          year = date_obj.year
          month = date_obj.strftime('%m')
          formatted_date = date_obj.strftime('%Y-%m-%d')
          
          object_key = "us_options_opra/day_aggs_v1/#{year}/#{month}/#{formatted_date}.csv.gz"
          local_file_path ||= "./#{formatted_date}_day_aggs.csv.gz"
          
          download_file(object_key, local_file_path)
        end

        # us_options_opra/minute_aggs_v1
        def get_min_aggs(date, local_file_path = nil)
          date_obj = Date.parse(date.to_s)
          year = date_obj.year
          month = date_obj.strftime('%m')
          formatted_date = date_obj.strftime('%Y-%m-%d')
          
          object_key = "us_options_opra/minute_aggs_v1/#{year}/#{month}/#{formatted_date}.csv.gz"
          local_file_path ||= "./#{formatted_date}_minute_aggs.csv.gz"
          
          download_file(object_key, local_file_path)
        end


        def list_aggs(ticker, multiplier, timespan, from, to, **options)
          # NOTE: https://polygon.io/docs/rest/options/aggregates/custom-bars
          path = "/v2/aggs/ticker/#{ticker}/range/#{multiplier}/#{timespan}/#{from}/#{to}"
          query_params = {
            adjusted: options[:adjusted] || true,
            sort: options[:sort] || 'asc',
            limit: options[:limit] || 5000
          }
          get(path, query_params)
        end

        private

        def s3_client
          @s3_client ||= Aws::S3::Client.new(
            access_key_id: @aws_access_key_id,
            secret_access_key: @aws_secret_access_key,
            endpoint: 'https://files.polygon.io',
            force_path_style: true,
            signature_version: 's3v4'
          )
        end

        def download_file(object_key, local_file_path)
          bucket_name = 'flatfiles'
          
          puts "Downloading file '#{object_key}' from bucket '#{bucket_name}'..."
          
          s3_client.get_object(
            bucket: bucket_name,
            key: object_key,
            response_target: local_file_path
          )
          
          puts "File downloaded to: #{local_file_path}"
          local_file_path
        rescue Aws::S3::Errors::NoSuchKey
          raise "File not found: #{object_key}"
        rescue StandardError => e
          raise "Download failed: #{e.message}"
        end

        def get(path, query_params = {})
          dest = URI("#{BASE_URL}#{path}")
          query_params[:apikey] = @api_key
          dest.query = URI.encode_www_form(query_params) if query_params.any?

          http = Net::HTTP.new(dest.host, dest.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(dest)
          response = http.request(request)

          case response.code.to_i
          when 200
            JSON.parse(response.body)
          when 401
            raise "Unauthorized: Invalid API key"
          when 429
            raise "Rate limit exceeded"
          else
            raise "HTTP Error #{response.code}: #{response.message}"
          end
        rescue JSON::ParserError => e
          raise "Invalid JSON response: #{e.message}"
        rescue StandardError => e
          raise "Request failed: #{e.message}"
        end
      end
    end
  end
end
