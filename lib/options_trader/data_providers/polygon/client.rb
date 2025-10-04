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

        def get_option_chain(
          symbol,
          datetime:,
          from_date: nil,
          to_date: nil,
          agg_size: "min",
          contract_type: 'ALL',
          strike_range: 'ALL',
          days_to_expiration: nil,
          local_dir: "./"
        )
          raise ArgumentError, "datetime must be a DateTime object" unless datetime.is_a?(DateTime)
          raise ArgumentError, "local_dir is required" if local_dir.nil? || local_dir.empty?
          raise ArgumentError, "agg_size must be 'min' or 'day'" unless ["min", "day"].include?(agg_size)
          raise ArgumentError, "from_date must be a Date object" if from_date && !from_date.is_a?(Date)
          raise ArgumentError, "to_date must be a Date object" if to_date && !to_date.is_a?(Date)
          raise ArgumentError, "from_date must be before or equal to to_date" if from_date && to_date && from_date > to_date
          raise ArgumentError, "contract_type must be 'CALL', 'PUT', or 'ALL'" unless ['CALL', 'PUT', 'ALL'].include?(contract_type)
          raise ArgumentError, "strike_range must be 'ITM', 'OTM', 'NTM', or 'ALL'" unless ['ITM', 'OTM', 'NTM', 'ALL'].include?(strike_range)
          raise ArgumentError, "days_to_expiration must be an integer" if days_to_expiration && !days_to_expiration.is_a?(Integer)

          # Convert days_to_expiration to date filtering if provided
          if days_to_expiration
            target_expiration = datetime.to_date + days_to_expiration
            from_date = target_expiration
            to_date = target_expiration
          end

          aggs_type = agg_size == 'min' ? 'minute_aggs_v1' : 'day_aggs_v1'
          target_date = datetime.to_date

          csv_file_path = underlying_aggs_file_path(
            aggs_type,
            symbol,
            local_dir,
            target_date.year,
            target_date.strftime('%m'),
            target_date.strftime('%d')
          )

          unless File.exist?(csv_file_path)
            return []
          end

          all_records = []
          target_timestamp_ns = (datetime.to_time.to_f * 1_000_000_000).to_i

          # First pass: collect all records and find closest timestamp for minute aggregates
          CSV.foreach(csv_file_path, headers: true) do |row|
            ticker = row['ticker']
            row_hash = row.to_h
            match = ticker.match(/^O:([A-Z]+)(\d{6})([CP])(\d{8})$/)

            next unless match

            root_symbol, exp_date, put_or_call, strike_raw = match.captures

            # Parse expiration date (YYMMDD -> Date)
            exp_year = 2000 + exp_date[0..1].to_i
            exp_month = exp_date[2..3].to_i
            exp_day = exp_date[4..5].to_i
            expiration_date = Date.new(exp_year, exp_month, exp_day)

            strike_price = strike_raw.to_f / 1000.0

            # Filter by expiration date if specified
            if to_date && !from_date
              # If only to_date is provided, filter for exact match
              next unless expiration_date == to_date
            elsif from_date && to_date
              # If both dates provided, filter for range
              next unless expiration_date >= from_date && expiration_date <= to_date
            elsif from_date
              # If only from_date provided, filter for dates >= from_date
              next unless expiration_date >= from_date
            end

            # Convert unix nanosecond timestamp to datetime
            record_datetime = nil
            if row_hash['window_start']
              timestamp_ns = row_hash['window_start'].to_i
              timestamp_s = timestamp_ns / 1_000_000_000.0
              record_datetime = Time.at(timestamp_s).to_datetime
            end

            option = OptionsTrader::DataObjects::Option.new(
              symbol: ticker,
              underlying_symbol: root_symbol,
              strike: strike_price,
              put_call: put_or_call == 'C' ? 'CALL' : 'PUT',
              mark: row_hash['close'].to_f,
              underlying_price: nil, # TODO: Fetch underlying price if needed
              expiration_date: expiration_date,
              total_volume: row_hash['volume'].to_i,
              option_root: root_symbol,
              open: row_hash['open'].to_f,
              high: row_hash['high'].to_f,
              low: row_hash['low'].to_f,
              close: row_hash['close'].to_f,
              timestamp: record_datetime
            )

            all_records << {
              option: option,
              window_start_ns: timestamp_ns,
              time_diff: (timestamp_ns - target_timestamp_ns).abs
            }
          end

          options = if agg_size == "min"
            # For minute aggregates, find the closest timestamp and return all records with that timestamp
            return OptionsTrader::DataObjects::OptionsChain.new(symbol: symbol) if all_records.empty?

            closest_time_diff = all_records.min_by { |record| record[:time_diff] }[:time_diff]
            closest_records = all_records.select { |record| record[:time_diff] == closest_time_diff }

            closest_records.map { |record| record[:option] }.sort_by(&:symbol)
          else
            all_records.map { |record| record[:option] }.sort_by(&:symbol)
          end

          # Apply contract type filtering
          filtered_options = options
          if contract_type != 'ALL'
            filtered_options = filtered_options.select { |opt| opt.put_call == contract_type }
          end

          # TODO: Apply strike range filtering (ITM, OTM, NTM) - requires underlying price
          # Note: Strike range filtering would need underlying price data which is not available in aggregate data
          # This could be implemented by fetching current underlying price or using a reference price

          # Separate calls and puts after filtering
          call_opts = filtered_options.select { |opt| opt.put_call == 'CALL' }
          put_opts = filtered_options.select { |opt| opt.put_call == 'PUT' }

          OptionsTrader::DataObjects::OptionsChain.new(
            symbol: symbol,
            underlying_price: nil, # Not available in aggregate data
            call_opts: call_opts,
            put_opts: put_opts
          )
        end

        def download_day_aggs(date, local_dir: "./")
          raise ArgumentError, "date must be a Date object" unless date.is_a?(Date)
          raise ArgumentError, "local_dir is required" if local_dir.nil? || local_dir.empty?

          year = date.year
          month = date.strftime('%m')
          formatted_date = date.strftime('%Y-%m-%d')

          aggs_type = "day_aggs_v1"

          csv_path = download_file(aggs_type, local_dir, year, month, formatted_date).then do |gz_file_path|
            unzip_file(gz_file_path)
            File.delete(gz_file_path) if File.exist?(gz_file_path)
          end
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

        def underlying_aggs_file_path(aggs_type, underlying_symbol, local_dir, year, month, day)
          local_dir ||= "."
          filename = "#{underlying_symbol}.csv"
          File.join(local_dir, aggs_type, year.to_s, month.to_s, day.to_s, filename)
        end

        def aggs_file_path(aggs_type, local_dir, year, month, formatted_date)
          local_dir ||= "."
          filename = "#{formatted_date}.csv"

          File.join(local_dir, aggs_type, year.to_s, month.to_s, filename)
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