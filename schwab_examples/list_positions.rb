#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fetch SPX option chains from today to 7 days out
# Outputs CSV files to the data/ directory
# Usage: ruby bin/fetch_spx_option_chains

require "pry"
require "bundler/setup"
require "schwab_rb"
require "dotenv"
require "date"
require "csv"
require "fileutils"

Dotenv.load

SchwabRb.configure do |config|
  config.log_file = "./tmp/schwab_rb.log"
  config.log_level = "DEBUG"
  config.silence_output = false
end

def create_client
  token_path = ENV["SCHWAB_TOKEN_PATH"] || File.join(Dir.home, ".schwab_rb", "token.json")

  SchwabRb::Auth.init_client_easy(
    ENV.fetch("SCHWAB_API_KEY"),
    ENV.fetch("SCHWAB_APP_SECRET"),
    ENV.fetch("SCHWAB_APP_CALLBACK_URL"),
    token_path
  )
end

schwab = create_client
acct = schwab.get_account(account_name: "TRADING_ACCOUNT", fields: [:positions])

spx_opt_positions = acct.positions.select { |pos| pos.instrument.asset_type == "OPTION" && pos.instrument.symbol.start_with?("SPXW") }

spx_opt_positions.each do |pos|
  puts pos.symbol
end

binding.pry