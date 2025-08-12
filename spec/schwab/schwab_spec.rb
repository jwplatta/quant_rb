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
    let(:quote_data) { JSON.parse(File.read('spec/fixtures/quotes/NVDA_quote.json'), symbolize_names: true) }
    let(:quote_object) { SchwabRb::DataObjects::EquityQuote.new(quote_data[:NVDA].merge(symbol: 'NVDA')) }

    it 'fetches and returns a quote for a symbol' do
      expect(mock_client).to receive(:get_quote).with('NVDA', return_data_objects: true).and_return(quote_object)

      quote = schwab_instance.quote('NVDA')
      expect(quote).to be_an_instance_of(SchwabRb::DataObjects::EquityQuote)
      expect(quote.symbol).to eq('NVDA')
    end
  end

  describe '#quotes' do
    let(:nvda_data) { JSON.parse(File.read('spec/fixtures/quotes/NVDA_quote.json'), symbolize_names: true) }
    let(:spx_data) { JSON.parse(File.read('spec/fixtures/quotes/$SPX_quote.json'), symbolize_names: true) }
    let(:quotes_objects) do
      [
        SchwabRb::DataObjects::EquityQuote.new(nvda_data[:NVDA].merge(symbol: 'NVDA')),
        SchwabRb::DataObjects::IndexQuote.new(spx_data[:'$SPX'].merge(symbol: '$SPX'))
      ]
    end

    it 'fetches and returns quotes for multiple symbols' do
      expect(mock_client).to receive(:get_quotes).with(['NVDA', '$SPX'], return_data_objects: true).and_return(quotes_objects)

      quotes = schwab_instance.quotes(['NVDA', '$SPX'])
      expect(quotes).to be_an_instance_of(Array)
      expect(quotes.size).to eq(2)

      expect(quotes.map(&:class)).to include(SchwabRb::DataObjects::EquityQuote, SchwabRb::DataObjects::IndexQuote)
      expect(quotes.map(&:symbol).sort).to eq(['$SPX', 'NVDA'].sort)
    end
  end

  describe '#option_chain' do
    let(:option_chain_data) { JSON.parse(File.read("spec/fixtures/option_chains/ACME_calls.json"), symbolize_names: true) }
    let(:option_chain_object) { SchwabRb::DataObjects::OptionChain.build(option_chain_data) }

    it 'fetches and returns an option chain for a symbol' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: Date.today + 30})
        .and_return(option_chain_object)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         to_date: Date.today + 30)

      expect(chain).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
    end

    it 'uses days_to_expiration when provided' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', days_to_expiration: 30})
        .and_return(option_chain_object)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         days_to_expiration: 30)

      expect(chain).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
    end

    it 'does not cache results between calls' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_object)

      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')
      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      expect(chain1).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
    end

    it 'does not use caching at all' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_object)

      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      expect(chain1).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(SchwabRb::DataObjects::OptionChain)
    end
  end

  describe '#account' do
    let(:account_data) { JSON.parse(File.read('spec/fixtures/account.json'), symbolize_names: true) }
    let(:account_object) { SchwabRb::DataObjects::Account.build(account_data) }

    it 'fetches and returns account information' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: nil, return_data_objects: true)
        .and_return(account_object)

      account = schwab_instance.account
      expect(account).to be_an_instance_of(SchwabRb::DataObjects::Account)
      expect(account.account_number).to eq('11111111')
    end

    it 'accepts optional fields parameter' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: 'positions,orders', return_data_objects: true)
        .and_return(account_object)

      account = schwab_instance.account(fields: 'positions,orders')
      expect(account).to be_an_instance_of(SchwabRb::DataObjects::Account)
    end
  end

  describe '#transactions' do
    let(:transactions_data) { JSON.parse(File.read('spec/fixtures/transactions.json'), symbolize_names: true) }
    let(:transactions_objects) { transactions_data.map { |tx| SchwabRb::DataObjects::Transaction.build(tx) } }

    it 'fetches and returns transactions' do
      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ', return_data_objects: true)
        .and_return(transactions_objects)

      transactions = schwab_instance.transactions
      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.size).to eq(2)
      expect(transactions.first).to be_an_instance_of(SchwabRb::DataObjects::Transaction)
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
                symbol: 'MRVL',
                return_data_objects: true
              })
        .and_return(transactions_objects)

      transactions = schwab_instance.transactions(
        from_date: from_date,
        to_date: to_date,
        transaction_types: 'TRADE',
        symbol: 'MRVL'
      )

      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.first).to be_an_instance_of(SchwabRb::DataObjects::Transaction)
      expect(transactions.first.transfer_items.size).to be > 0
      fee_items = transactions.first.transfer_items.select(&:fee_type)
      expect(fee_items).not_to be_empty
    end
  end

  describe '#account_orders' do
    let(:orders_data) { JSON.parse(File.read('spec/fixtures/orders.json'), symbolize_names: true) }
    let(:orders_objects) { orders_data.map { |order| SchwabRb::DataObjects::Order.build(order) } }

    it 'fetches and returns orders for the account' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)
      status = 'FILLED'

      expect(mock_client).to receive(:get_account_orders)
        .with('ABC123XYZ', from_entered_datetime: from_date, to_entered_datetime: to_date, status: status, return_data_objects: true)
        .and_return(orders_objects)

      orders = schwab_instance.account_orders(from_date: from_date, to_date: to_date, status: status)
      expect(orders).to be_an_instance_of(Array)
      expect(orders.first).to be_an_instance_of(SchwabRb::DataObjects::Order)
      expect(orders.first.status).to eq('FILLED')
    end
  end

  describe '#preview_order' do
    let(:preview_data) { JSON.parse(File.read('spec/fixtures/order_preview.json'), symbolize_names: true) }
    let(:preview_object) do
      # Create a mock OrderPreview object since the schwab_rb library may have issues
      # with the complex commission/fee structure in the fixture
      obj = double('SchwabRb::DataObjects::OrderPreview')
      allow(obj).to receive(:accepted?).and_return(true)
      allow(obj).to receive(:commission).and_return(1.3) # 0.65 * 2 legs
      allow(obj).to receive(:fees).and_return(1.14) # (0.01 + 0.56) * 2 legs
      allow(obj).to receive(:order_id).and_return(0)
      allow(obj).to receive(:status).and_return('ACCEPTED')
      allow(obj).to receive(:price).and_return(1.25)
      allow(obj).to receive(:quantity).and_return(1.0)
      # Mock the to_h method since the schwab.rb code calls it for file writing
      allow(obj).to receive(:to_h).and_return({
        order_id: 0,
        status: 'ACCEPTED',
        price: 1.25,
        quantity: 1.0,
        commission: 1.3,
        fees: 1.14
      })
      obj
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
        .with('ABC123XYZ', order_data, return_data_objects: true)
        .and_return(preview_object)

      preview = schwab_instance.preview_order(order_data)
      expect(preview).to respond_to(:accepted?)
      expect(preview).to respond_to(:commission)
      expect(preview).to respond_to(:fees)
      expect(preview.accepted?).to be true
      expect(preview.commission).to eq(1.3) # 0.65 * 2
      expect(preview.fees).to eq(1.14) # 0.01*2 + 0.56*2
    end
  end

  describe '#get_order' do
    let(:order_data) { JSON.parse(File.read('spec/fixtures/orders.json'), symbolize_names: true).first }
    let(:order_object) { SchwabRb::DataObjects::Order.build(order_data) }

    it 'fetches a specific order by ID' do
      order_id = '1002613435352'

      expect(mock_client).to receive(:get_order)
        .with(order_id, 'ABC123XYZ', return_data_objects: true)
        .and_return(order_object)

      order = schwab_instance.get_order(order_id)
      expect(order).to be_an_instance_of(SchwabRb::DataObjects::Order)
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
      OptionsTrader.instance_variable_set(:@configuration, nil)
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

    describe '#available_accounts' do
      it 'returns available account names' do
        accounts = schwab_instance.available_accounts
        expect(accounts).to contain_exactly('main', 'trading')
      end
    end

    describe '#account_exists?' do
      it 'returns true for existing accounts' do
        expect(schwab_instance.account_exists?('main')).to be true
        expect(schwab_instance.account_exists?('trading')).to be true
      end

      it 'returns false for non-existing accounts' do
        expect(schwab_instance.account_exists?('unknown')).to be false
      end
    end

    describe '#switch_account' do
      it 'switches to a valid account' do
        schwab_instance.switch_account('trading')
        expect(schwab_instance.current_account_name).to eq('trading')
      end

      it 'raises an error for invalid accounts' do
        expect {
          schwab_instance.switch_account('unknown')
        }.to raise_error("Account 'unknown' not found. Available accounts: main, trading")
      end
    end
  end
end
