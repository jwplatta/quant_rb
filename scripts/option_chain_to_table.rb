# frozen_string_literal: true

require 'json'
require 'csv'

json_path = File.expand_path('../spec/fixtures/option_chains/SPX_05_20_2025_option_chain.json', __dir__)
csv_path = './SPX_05_20_2025_option_chain.csv'

data = JSON.parse(File.read(json_path))

underlying_symbol = data['symbol']
underlying_price = data['underlyingPrice']

rows = []

def extract_options(map, contract_type, underlying_symbol, underlying_price)
  rows = []
  map.each do |_exp_date, strikes|
    strikes.each do |_strike, contracts|
      contracts.each do |contract|
        rows << {
          symbol: contract['symbol'],
          underlying_symbol: underlying_symbol,
          underlying_price: underlying_price,
          contract_type: contract_type,
          strike: contract['strikePrice'],
          expiration_date: contract['expirationDate'],
          bid: contract['bid'],
          ask: contract['ask'],
          mark: contract['mark'],
          last: contract['last'],
          delta: contract['delta'],
          open_interest: contract['openInterest'],
          volume: contract['totalVolume'],
          option_root: contract['optionRoot'],
          expiration_type: contract['expirationType'],
          intrinsic_value: contract['intrinsicValue'],
          extrinsic_value: contract['extrinsicValue'],
          time_value: contract['timeValue'],
          volatility: contract['volatility'],
          high_52_week: contract['high52Week'],
          low_52_week: contract['low52Week'],
          gamma: contract['gamma'],
          theta: contract['theta'],
          vega: contract['vega'],
          rho: contract['rho'],
          bid_size: contract['bidSize'],
          ask_size: contract['askSize'],
          high_price: contract['highPrice'],
          low_price: contract['lowPrice'],
          open_price: contract['openPrice'],
          close_price: contract['closePrice']
        }
      end
    end
  end
  rows
end

if data['callExpDateMap']
  rows += extract_options(data['callExpDateMap'], 'CALL', underlying_symbol, underlying_price)
end

if data['putExpDateMap']
  rows += extract_options(data['putExpDateMap'], 'PUT', underlying_symbol, underlying_price)
end

CSV.open(csv_path, 'w') do |csv|
  csv << %w[symbol underlying_symbol underlying_price contract_type strike expiration_date bid ask mark last delta open_interest volume option_root expiration_type intrinsic_value extrinsic_value time_value volatility high_52_week low_52_week gamma theta vega rho bid_size ask_size high_price low_price open_price close_price]
  rows.each do |row|
    csv << row.values
  end
end

puts "CSV written to #{csv_path}"
