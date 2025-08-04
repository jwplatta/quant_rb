# frozen_string_literal: true

FactoryBot.define do
  factory :option_chain_history, class: 'OptionsTrader::OptionChainHistory' do
    symbol { 'SPX250810C06410' }
    root_symbol { 'SPX' }
    underlying_symbol { '$SPX' }
    expiration_date { Date.parse('2025-08-10') }
    strike { 6410.00 }
    contract_type { 'CALL' }

    # Pricing data
    bid { 124.20 }
    ask { 126.80 }
    mark { 125.50 }
    last_price { 125.00 }

    # Underlying data
    underlying_price { 6532.15 }

    # Greeks
    delta { 0.64 }
    theta { -2.47 }
    vega { 8.95 }
    gamma { 0.0046 }
    rho { 0.14 }

    # Volume/Interest
    volume { 12 }
    open_interest { 1245 }
    bid_size { 10 }
    ask_size { 15 }

    # Option data
    option_root { 'SPX' }
    expiration_type { 'W' }
    intrinsic_value { 122.15 }
    extrinsic_value { 2.85 }
    time_value { 2.85 }
    volatility { 0.18 }

    # Price history
    high_52_week { 200.00 }
    low_52_week { 0.50 }
    high_price { 126.50 }
    low_price { 124.00 }
    open_price { 124.50 }
    close_price { 125.00 }

    # Bitemporal timestamps
    valid_time { Time.parse('2025-08-01 10:00:00') }
    transaction_time { Time.current }

    factory :spx_6410_call do
      symbol { 'SPXW250810C06410' }
      root_symbol { 'SPXW' }
      underlying_symbol { '$SPX' }
      expiration_date { Date.parse('2025-08-10') }
      strike { 6410.00 }
      contract_type { 'CALL' }
      option_root { 'SPXW' }
      expiration_type { 'W' }
    end

    factory :spx_6410_put do
      symbol { 'SPXW250810P06410' }
      root_symbol { 'SPXW' }
      underlying_symbol { '$SPX' }
      expiration_date { Date.parse('2025-08-10') }
      strike { 6410.00 }
      contract_type { 'PUT' }
      option_root { 'SPXW' }
      expiration_type { 'W' }
    end
  end
end