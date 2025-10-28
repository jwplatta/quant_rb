RSpec.shared_context 'realistic SPX option chain' do
  let(:underlying_price) { 6875.16 }
  let(:underlying_symbol) { 'SPXW' }
  let(:expiration_date) { Date.new(2025, 10, 28) }
  let(:dte) { 1 }
  let(:timestamp) { Time.now }
  let(:features) do
    {
      vvix: 97.4,
      vix9d: 14.64,
      vix1d: 8.94
    }
  end

  let(:put_opts) do
    [
      create_option(strike: 5800, contract_type: 'PUT', mark: 0.025),
      create_option(strike: 6025, contract_type: 'PUT', mark: 0.025),
      create_option(strike: 6300, contract_type: 'PUT', mark: 0.025),
      create_option(strike: 6480, contract_type: 'PUT', mark: 0.075),
      create_option(strike: 6610, contract_type: 'PUT', mark: 0.025),
      create_option(strike: 6700, contract_type: 'PUT', mark: 0.275),
      create_option(strike: 6805, contract_type: 'PUT', mark: 1.45),
      create_option(strike: 6850, contract_type: 'PUT', mark: 4.85),
      create_option(strike: 6860, contract_type: 'PUT', mark: 6.9),
      create_option(strike: 6870, contract_type: 'PUT', mark: 9.9),
      create_option(strike: 6875, contract_type: 'PUT', mark: 12.0),
      create_option(strike: 6890, contract_type: 'PUT', mark: 20.65),
      create_option(strike: 6900, contract_type: 'PUT', mark: 28.35),
      create_option(strike: 6925, contract_type: 'PUT', mark: 51.3),
      create_option(strike: 7000, contract_type: 'PUT', mark: 125.7),
      create_option(strike: 7200, contract_type: 'PUT', mark: 325.6),
      create_option(strike: 8000, contract_type: 'PUT', mark: 1125.75)
    ]
  end

  let(:call_opts) do
    [
      create_option(strike: 6775, contract_type: 'CALL', mark: 101.3),
      create_option(strike: 6800, contract_type: 'CALL', mark: 76.2),
      create_option(strike: 6810, contract_type: 'CALL', mark: 66.55),
      create_option(strike: 6830, contract_type: 'CALL', mark: 47.6),
      create_option(strike: 6840, contract_type: 'CALL', mark: 38.25),
      create_option(strike: 6850, contract_type: 'CALL', mark: 30.3),
      create_option(strike: 6860, contract_type: 'CALL', mark: 22.2),
      create_option(strike: 6875, contract_type: 'CALL', mark: 11.9),
      create_option(strike: 6880, contract_type: 'CALL', mark: 9.35),
      create_option(strike: 6890, contract_type: 'CALL', mark: 5.4),
      create_option(strike: 6900, contract_type: 'CALL', mark: 3.0),
      create_option(strike: 7000, contract_type: 'CALL', mark: 0.025),
      create_option(strike: 7000, contract_type: 'CALL', mark: 0.1)
    ]
  end

  let(:option_chain) do
    OptionsTrader::DataObjects::OptionsChain.new(
      symbol: underlying_symbol,
      underlying_price: underlying_price,
      call_opts: call_opts,
      put_opts: put_opts
    )
  end

  def create_option(strike:, contract_type:, mark:)
    OptionsTrader::DataObjects::Option.new(
      symbol: "SPXW#{expiration_date.strftime('%Y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i.to_s.rjust(8, '0')}",
      underlying_symbol: underlying_symbol,
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: dte,
      timestamp: timestamp
    )
  end
end
