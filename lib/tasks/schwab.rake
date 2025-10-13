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
