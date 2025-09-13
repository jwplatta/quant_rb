#!/usr/bin/env ruby

require_relative '../config/environment'
require_relative '../lib/options_trader'
require 'date'
require 'dotenv'
require 'net/http'
require 'uri'

# Load environment from repository .env (explicit path). Do not print or read the file contents here.
Dotenv.load(File.expand_path('../.env', __dir__))

# Read the Polygon API key from ENV
POYLGON_OPTIONS_KEY = ENV['POLYGON_OPTIONS_API_KEY']
option_symbol = "O:SPXW250818C06460000"

class PolygonClient
  def initialize(api_key)
    @api_key = api_key
  end

  # Perform a GET to the given path (including query string). Returns the Net::HTTP::Response.
  def get(path, query_params = {})
    uri = URI("https://api.polygon.io#{path}")
    uri.query = URI.encode_www_form(query_params) unless query_params.empty?

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      req = Net::HTTP::Get.new(uri)
      http.request(req)
    end
  end
end

client = PolygonClient.new(POYLGON_OPTIONS_KEY)
path = "/v2/aggs/ticker/#{option_symbol}/range/1/minute/1754921040000/1854921040000"
query = { 'adjusted' => 'true', 'sort' => 'asc', 'limit' => '120', 'apiKey' => POYLGON_OPTIONS_KEY }

# Execute the request and print the response status and body (caller may run this to perform network call).
response = client.get(path, query)
puts "#{response.code} #{response.message}"
puts response.body

#######################
# Polygon example 2025-08-11 14:15:00
valid_time_s = "2025-08-11 14:15:00" # NOTE: UTC
valid_datetime = DateTime.parse(valid_time_s).new_offset('-04:00')
valid_time_ms = valid_datetime.to_time.to_i * 1000



# delta = 0.24
# expiration date = "2025-08-18"
# strike = 6460.0
# contract_type = CALL
# mark = 13.90
# bid = 13.80
# ask = 14.0
# underlying_price = 6393.61
# low_price = 12.80
# high_price = 14.13
# close_price = 15.00
# valid_time = 2025-08-11 14:04:18
