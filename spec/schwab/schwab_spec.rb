# frozen_string_literal: true

RSpec.describe OptionsTrader::Schwab do
  let(:test_class) do
    Class.new do
      include OptionsTrader::Schwab
    end
  end

  let(:schwab_instance) { test_class.new }
  let(:mock_client) { double('SchwabRb::Client') }

  before do
    allow(schwab_instance).to receive(:client).and_return(mock_client)
    allow(schwab_instance).to receive(:account_hash).and_return('ABC123XYZ')

    test_class.clear_option_chain_cache if test_class.respond_to?(:clear_option_chain_cache)
  end

  describe '#quote' do
    let(:quote_response) do
      instance_double('Response', body: File.read('spec/fixtures/quotes/NVDA_quote.json'))
    end

    it 'fetches and returns a quote for a symbol' do
      expect(mock_client).to receive(:get_quote).with('NVDA').and_return(quote_response)

      quote = schwab_instance.quote('NVDA')
      expect(quote).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::EquityQuote)
      expect(quote.symbol).to eq('NVDA')
    end
  end

  describe '#quotes' do
    let(:quotes_response) do
      quotes_data = {
        'NVDA' => JSON.parse(File.read('spec/fixtures/quotes/NVDA_quote.json'))['NVDA'],
        '$SPX' => JSON.parse(File.read('spec/fixtures/quotes/$SPX_quote.json'))['$SPX']
      }
      instance_double('Response', body: quotes_data.to_json)
    end

    it 'fetches and returns quotes for multiple symbols' do
      expect(mock_client).to receive(:get_quotes).with(['NVDA', '$SPX']).and_return(quotes_response)

      quotes = schwab_instance.quotes(['NVDA', '$SPX'])
      expect(quotes).to be_an_instance_of(Array)
      expect(quotes.size).to eq(2)

      expect(quotes.map(&:class)).to include(OptionsTrader::Schwab::DataObjects::EquityQuote, OptionsTrader::Schwab::DataObjects::IndexQuote)
      expect(quotes.map(&:symbol).sort).to eq(['$SPX', 'NVDA'].sort)
    end
  end

  describe '#option_chain' do
    let(:option_chain_response) do
      instance_double('Response', body: File.read("spec/fixtures/option_chains/ACME_calls.json"))
    end

    it 'fetches and returns an option chain for a symbol' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: Date.today + 30})
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         to_date: Date.today + 30)

      expect(chain).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
    end

    it 'uses days_to_expiration when provided' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', days_to_expiration: 30})
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         days_to_expiration: 30)

      expect(chain).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
    end

    it 'does not cache results between calls' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_response)

      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')
      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      expect(chain1).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
    end

    it 'does not use caching at all' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_response)

      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      expect(chain1).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OptionChain)
    end
  end

  describe '#account' do
    let(:account_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/account.json'))
    end

    it 'fetches and returns account information' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: nil)
        .and_return(account_response)

      account = schwab_instance.account
      expect(account).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Account)
      expect(account.account_number).to eq('11111111')
    end

    it 'accepts optional fields parameter' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: 'positions,orders')
        .and_return(account_response)

      account = schwab_instance.account(fields: 'positions,orders')
      expect(account).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Account)
    end
  end

  describe '#transactions' do
    let(:transactions_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/transactions.json'))
    end

    it 'fetches and returns transactions' do
      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ')
        .and_return(transactions_response)

      transactions = schwab_instance.transactions
      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.size).to eq(2)
      expect(transactions.first).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Transaction)
      expect(transactions.first.type).to eq('TRADE')
      expect(transactions.first.order_id).to eq('1002613435352')
      expect(transactions.first.transfer_items).to be_an_instance_of(Array)
      expect(transactions.first.transfer_items.first.instrument.symbol).to eq('MRVL  250321C00155000')
    end

    it 'accepts optional parameters' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)

      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ', {
                start_date: from_date,
                end_date: to_date,
                transaction_types: 'TRADE',
                symbol: 'MRVL'
              })
        .and_return(transactions_response)

      transactions = schwab_instance.transactions(
        from_date: from_date,
        to_date: to_date,
        transaction_types: 'TRADE',
        symbol: 'MRVL'
      )

      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.first).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Transaction)
      expect(transactions.first.transfer_items.size).to be > 0
      fee_items = transactions.first.transfer_items.select(&:fee_type)
      expect(fee_items).not_to be_empty
    end
  end

  describe '#account_orders' do
    let(:orders_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/orders.json'))
    end

    it 'fetches and returns orders for the account' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)
      status = 'FILLED'

      expect(mock_client).to receive(:get_account_orders)
        .with('ABC123XYZ', from_entered_datetime: from_date, to_entered_datetime: to_date, status: status)
        .and_return(orders_response)

      orders = schwab_instance.account_orders(from_date: from_date, to_date: to_date, status: status)
      expect(orders).to be_an_instance_of(Array)
      expect(orders.first).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Order)
      expect(orders.first.status).to eq('FILLED')
    end
  end

  describe '#preview_order' do
    let(:preview_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/order_preview.json'))
    end

    it 'previews an order and returns an order preview' do
      order_data = {
        orderType: 'NET_CREDIT',
        session: 'NORMAL',
        duration: 'DAY',
        orderStrategyType: 'SINGLE',
        price: 1.25,
        orderLegs: [
          {
            instrument: {
              symbol: 'SPX  250317P04350000'
            },
            instruction: 'SELL_TO_OPEN',
            quantity: 1
          },
          {
            instrument: {
              symbol: 'SPX  250317P04250000'
            },
            instruction: 'BUY_TO_OPEN',
            quantity: 1
          }
        ]
      }

      expect(mock_client).to receive(:preview_order)
        .with('ABC123XYZ', order_data)
        .and_return(preview_response)

      preview = schwab_instance.preview_order(order_data)
      expect(preview).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::OrderPreview)
      expect(preview.accepted?).to be true
      expect(preview.commission).to eq(1.3) # 0.65 * 2
      expect(preview.fees).to eq(1.14) # 0.01*2 + 0.56*2
    end
  end

  describe '#get_order' do
    let(:order_response) do
      order_data = JSON.parse(File.read('spec/fixtures/orders.json'), symbolize_names: true).first
      instance_double('Response', body: order_data.to_json)
    end

    it 'fetches a specific order by ID' do
      order_id = '1002613435352'

      expect(mock_client).to receive(:get_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(order_response)

      order = schwab_instance.get_order(order_id)
      expect(order).to be_an_instance_of(OptionsTrader::Schwab::DataObjects::Order)
      expect(order.order_id.to_s).to eq('1002613435352')
    end
  end

  describe '#cancel_order' do
    let(:cancel_response) do
      instance_double('Response', status: 200)
    end

    it 'cancels an order and returns success status' do
      order_id = 1_002_613_435_352

      expect(mock_client).to receive(:cancel_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(cancel_response)

      result = schwab_instance.cancel_order(order_id)
      expect(result).to be true
    end
  end

  describe 'account management' do
    before do
      OptionsTrader.configuration.add_account('main', '12345678')
      OptionsTrader.configuration.add_account('trading', '87654321')
      OptionsTrader::Schwab::Accounts.instance_variable_set(:@accounts, nil)
      OptionsTrader::Schwab::Accounts.instance_variable_set(:@account_hashes, nil)
    end

    describe '#set_account' do
      it 'sets the current account name' do
        schwab_instance.set_account('main')
        expect(schwab_instance.current_account_name).to eq('main')
      end
    end

    describe '#current_account_name' do
      it 'returns the current account name when set' do
        schwab_instance.set_account('trading')
        expect(schwab_instance.current_account_name).to eq('trading')
      end

      it 'raises an error when no account is set' do
        expect {
          schwab_instance.current_account_name
        }.to raise_error("No account set. Call set_account(account_name) first.")
      end
    end

    describe '#current_account' do
      it 'returns an Accounts instance for the current account' do
        schwab_instance.set_account('main')
        account = schwab_instance.current_account

        expect(account).to be_an_instance_of(OptionsTrader::Schwab::Accounts)
        expect(account.account_number).to eq('12345678')
      end
    end

    describe '#build_order (account integration)' do
      before do
        schwab_instance.set_account('trading')

        allow(OptionsTrader::Schwab::OrderFactory).to receive(:build).and_return({})
      end

      it 'uses the current account number when building orders' do
        expect(OptionsTrader::Schwab::OrderFactory).to receive(:build).with(
          hash_including(account_number: '87654321')
        )

        schwab_instance.build_order(order_instruction: :open)
      end
    end
  end
end
