require "json"
require "net/http"
require "uri"
require "aws-sdk-s3"
require "singleton"
require "zip"
require "zlib"
require "fileutils"
require "csv"


module OptionsTrader
  module DataProviders
    module Polygon
      class Client
        include Singleton

        BASE_URL = 'https://api.polygon.io'
        FLATFILES_BUCKET_NAME = 'flatfiles'

        def initialize
          @api_key = ENV['POLYGON_OPTIONS_API_KEY']
          @aws_access_key_id = ENV['POLYGON_AWS_ACCESS_KEY_ID']
          @aws_secret_access_key = ENV['POLYGON_AWS_SECRET_ACCESS_KEY']

          raise ArgumentError, "API key is required" if @api_key.nil? || @api_key.empty?
          raise ArgumentError, "AWS credentials are required for file downloads" if @aws_access_key_id.nil? || @aws_secret_access_key.nil?
        end

        def get_aggs(symbol:, start_datetime:, end_datetime: nil, agg_size: 'min', local_dir: "./")
        end

        def download_day_aggs(date, local_dir: "./")
          # NOTE: us_options_opra/day_aggs_v1
          raise ArgumentError, "date must be a Date object" unless date.is_a?(Date)
          raise ArgumentError, "local_dir is required" if local_dir.nil? || local_dir.empty?

          year = date.year
          month = date.strftime('%m')
          formatted_date = date.strftime('%Y-%m-%d')

          file_path = "us_options_opra/day_aggs_v1/#{year}/#{month}"
          filename = "#{formatted_date}.csv.gz"
          object_key = "#{file_path}/#{filename}"
          local_file_path ||= "#{local_dir}/#{year}/#{month}/#{filename}"

          download_file(object_key, local_file_path, local_dir, year, month, filename)
        end

        # us_options_opra/minute_aggs_v1
        def download_min_aggs(date, local_dir: "./")
          raise ArgumentError, "date must be a Date object" unless date.is_a?(Date)
          raise ArgumentError, "local_dir is required" if local_dir.nil? || local_dir.empty?

          year = date.year
          month = date.strftime('%m')
          formatted_date = date.strftime('%Y-%m-%d')

          aggs_type = "minute_aggs_v1"

          csv_path = download_file(aggs_type, local_dir, year, month, formatted_date).then do |gz_file_path|
            unzip_file(gz_file_path)
            File.delete(gz_file_path) if File.exist?(gz_file_path)
          end
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
            region: 'us-east-2',
            force_path_style: true,
            ssl_verify_peer: false,
            signature_version: 'v4',
            retry_limit: 0  # Disable retries for clearer error messages
          )
        end

        def unzip_file(gz_file_path)
          output_file_path = gz_file_path.sub(/\.gz\z/, '')
          begin
            Zlib::GzipReader.open(gz_file_path) do |gz|
              File.open(output_file_path, 'wb') do |out|
                IO.copy_stream(gz, out)
              end
            end
          rescue StandardError => e
            puts "Error unzipping file #{gz_file_path}: #{e.message}"
          end
          output_file_path
        end

        def download_file(aggs_type, local_dir, year, month, formatted_date)
          filename = "#{formatted_date}.csv.gz"
          file_path = "us_options_opra/#{aggs_type}/#{year}/#{month}"
          object_key = "#{file_path}/#{filename}"

          local_file_path ||= "#{local_dir}/#{year}/#{month}/#{filename}"

          unless Dir.exist?(local_dir)
            raise ArgumentError, "local_dir does not exist: #{local_dir}"
          end

          aggs_type_dir = File.join(local_dir, aggs_type)
          Dir.mkdir(aggs_type_dir) unless Dir.exist?(aggs_type_dir)

          year_dir = File.join(aggs_type_dir, year.to_s)
          Dir.mkdir(year_dir) unless Dir.exist?(year_dir)

          month_dir = File.join(year_dir, month.to_s)
          Dir.mkdir(month_dir) unless Dir.exist?(month_dir)

          local_file_path = File.join(month_dir, filename)

          s3_client.get_object(
            bucket: FLATFILES_BUCKET_NAME,
            key: object_key,
            response_target: local_file_path
          )

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