# frozen_string_literal: true

require 'json'
require 'csv'
require 'date'
require 'gruff'
require 'fileutils'
require 'schwab_rb'
require_relative '../options_trader'

OptionsTrader.configure do |config|
  config.log_file = "./tmp/options_trader.log"
  config.log_to_stdout = false
  config.log_level = :debug
end

class SchwabClient
  include OptionsTrader::Schwab
end

schwab_client = SchwabClient.new

namespace :schwab do
  desc 'Refresh Schwab token'
  task :refresh_token do
    script_path = File.join(Dir.pwd, 'bin', 'refresh_token.rb')
    sh "ruby #{script_path}"
    puts 'Token refreshed'
  end

  desc 'List available accounts'
  task :list_accounts => :environment do
    accounts = schwab_client.available_accounts
    if accounts.empty?
      puts "No accounts configured. Please configure accounts using:"
      puts "OptionsTrader.configure do |config|"
      puts "  config.add_account('account_name', 'account_number')"
      puts "end"
    else
      puts "Available accounts:"
      accounts.each do |account_name|
        account_number = OptionsTrader.account_number(account_name)
        puts "  #{account_name}: #{account_number}"
      end
    end
  end

  desc "Export Transactions by Order"
  task :export_transactions_by_order, [:account_names, :from_date, :to_date] => :environment do |_t, args|
    account_names = validate_account_names(schwab_client, args[:account_names])

    from_date = args[:from_date] ? Date.parse(args[:from_date]) : Date.today
    from_date = DateTime.new(from_date.year, from_date.month, from_date.day, 0, 0, 0)

    to_date = args[:to_date] ? Date.parse(args[:to_date]) : Date.today
    to_date = DateTime.new(to_date.year, to_date.month, to_date.day, 23, 59, 59)

    out_path = OptionsTrader::Exports::TransactionsByOrder.export(
      schwab_client: schwab_client,
      from_date: from_date,
      to_date: to_date,
      account_names: account_names
    )

    puts "Exported to: #{out_path}"
  end

  desc "Download price history to CSV file"
  task :download_price_history, [:symbol, :start_date, :end_date, :interval] => :environment do |_t, args|
    unless args[:symbol] && args[:start_date] && args[:interval]
      puts "Missing required parameters. Usage:"
      puts "rake schwab:download_price_history[SYMBOL,START_DATE,END_DATE,INTERVAL]"
      puts "Example: rake schwab:download_price_history['$SPX','2023-09-26','2023-09-27','1min']"
      exit 1
    end

    if args[:interval] != 'daily' && !args[:end_date]
      puts "END_DATE is required for intervals other than 'daily'"
      exit 1
    end

    valid_intervals = [
      OptionsTrader::Intervals::ONE_MIN,
      OptionsTrader::Intervals::FIVE_MIN,
      OptionsTrader::Intervals::TEN_MIN,
      OptionsTrader::Intervals::FIFTEEN_MIN,
      OptionsTrader::Intervals::THIRTY_MIN,
      OptionsTrader::Intervals::DAILY
    ]

    unless valid_intervals.include?(args[:interval])
      puts "Invalid interval: #{args[:interval]}"
      puts "Valid intervals: #{valid_intervals.join(', ')}"
      exit 1
    end

    begin
      start_date = Date.parse(args[:start_date])
      end_date = Date.parse(args[:end_date]) if args[:interval] != 'daily'

      if args[:interval] != 'daily' && start_date > end_date
        puts "Start date must be before or equal to end date"
        exit 1
      end
    rescue ArgumentError => e
      puts "Invalid date format: #{e.message}"
      puts "Please use format: YYYY-MM-DD"
      exit 1
    end

    base_path = ENV['HISTORICAL_FLATFILES_PATH']
    unless base_path
      puts "HISTORICAL_FLATFILES_PATH environment variable not set"
      exit 1
    end

    OptionsTrader::Services::SchwabExporter.export(
      symbol: args[:symbol],
      start_date: start_date,
      end_date: end_date,
      interval: args[:interval],
      output_dir: base_path
    )

    puts "Export completed for #{args[:symbol]} from #{start_date} to #{end_date} at #{args[:interval]} interval."
  end
end

def validate_account_names(client, accounts_arg)
  unless accounts_arg
    puts "No accounts specified. Please provide account name(s) as a parameter."
    puts "Examples:"
    puts "  Single account:    rake schwab:monthly_report[2025,main]"
    puts "  Multiple accounts: rake schwab:monthly_report[2025,\"main,trading|ira\"]"
    puts "Available accounts: #{client.available_accounts.join(', ')}"
    exit
  end

  account_names = accounts_arg.split('|').map(&:strip)
  available_accounts = client.available_accounts
  invalid_accounts = account_names - available_accounts

  unless invalid_accounts.empty?
    puts "Invalid accounts: #{invalid_accounts.join(', ')}"
    puts "Available accounts: #{available_accounts.join(', ')}"
    exit
  end

  account_names
end
