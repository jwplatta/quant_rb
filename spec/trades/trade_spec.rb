# frozen_string_literal: true

require 'rspec'
require 'securerandom'

RSpec.describe Platypi::Trades::Trade do
  let(:mock_strategy) do
    double('Strategy', to_h: {
      type: 'callspread',
      quantity: 1,
      underlying_symbol: 'SPY',
      short_leg: { symbol: 'SPY250620C00500000', strike: 500.0 },
      long_leg: { symbol: 'SPY250620C00510000', strike: 510.0 }
    })
  end

  let(:trade_id) { SecureRandom.uuid }
  let(:status) { Platypi::Trades::TRADE_STATUSES[:open] }

  # Mock journal for testing
  let(:mock_journal) { double('TradeJournal') }

  before do
    allow(Platypi::TradeJournal).to receive(:new).and_return(mock_journal)
    allow(mock_journal).to receive(:save_trade)
    allow(mock_journal).to receive(:load_trade)
    allow(mock_journal).to receive(:trade_history).and_return([])
    allow(mock_journal).to receive(:delete_trade)
    allow(mock_journal).to receive(:current_file_path).and_return('/tmp/test.json')
  end

  describe '#initialize' do
    it 'creates a journal instance with trade_id' do
      expect(Platypi::TradeJournal).to receive(:new).with(trade_id)

      described_class.new(
        strategy: mock_strategy,
        trade_id: trade_id,
        status: status
      )
    end

    it 'generates UUID if no trade_id provided' do
      expect(SecureRandom).to receive(:uuid).and_return('generated-uuid')
      expect(Platypi::TradeJournal).to receive(:new).with('generated-uuid')

      described_class.new(strategy: mock_strategy)
    end
  end

  describe '#open' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id, preview: false) }

    before do
      allow(trade).to receive(:preview_order)
      allow(trade).to receive(:send_order)
    end

    context 'in preview mode' do
      let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id, preview: true) }

      it 'sets status to PREVIEW_OPEN and saves' do
        expect(trade).to receive(:preview_order).with(mock_strategy, order_instruction: :open)
        expect(mock_journal).to receive(:save_trade).with(trade)

        trade.open

        expect(trade.status).to eq('PREVIEW_OPEN')
      end
    end

    context 'in live mode' do
      it 'sets status to OPEN and saves' do
        expect(trade).to receive(:send_order).with(mock_strategy, order_instruction: :open)
        expect(mock_journal).to receive(:save_trade).with(trade)

        trade.open

        expect(trade.status).to eq('OPEN')
      end
    end
  end

  describe '#exit' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id, preview: false) }

    before do
      allow(trade).to receive(:preview_order)
      allow(trade).to receive(:send_order)
    end

    context 'in preview mode' do
      let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id, preview: true) }

      it 'sets status to PREVIEW_EXIT and saves' do
        expect(trade).to receive(:preview_order).with(mock_strategy, order_instruction: :exit)
        expect(mock_journal).to receive(:save_trade).with(trade)

        trade.exit

        expect(trade.status).to eq('PREVIEW_EXIT')
      end
    end

    context 'in live mode' do
      it 'sets status to EXIT and saves' do
        expect(trade).to receive(:send_order).with(mock_strategy, order_instruction: :exit)
        expect(mock_journal).to receive(:save_trade).with(trade)

        trade.exit

        expect(trade.status).to eq('EXIT')
      end
    end
  end

  describe '#save' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }

    it 'delegates to journal save_trade' do
      expect(mock_journal).to receive(:save_trade).with(trade)
      trade.save
    end
  end

  describe '#reload' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }
    let(:reloaded_trade_data) do
      described_class.new(
        strategy: mock_strategy,
        trade_id: trade_id,
        status: 'EXIT',
        preview: false
      )
    end

    before do
      # Set up the reloaded trade to have order data
      allow(reloaded_trade_data).to receive(:order_id).and_return('order-123')
      allow(reloaded_trade_data).to receive(:order_status).and_return('FILLED')
      allow(reloaded_trade_data).to receive(:order_instruction).and_return(:exit)
      allow(reloaded_trade_data).to receive(:order_price).and_return(1.50)
      allow(reloaded_trade_data).to receive(:order_fees).and_return(2.30)
      allow(reloaded_trade_data).to receive(:order_commission).and_return(0.0)
      allow(reloaded_trade_data).to receive(:order_rejects).and_return([])
    end

    context 'when latest trade exists' do
      before do
        allow(mock_journal).to receive(:load_trade).and_return(reloaded_trade_data)
      end

      it 'updates current instance with latest state' do
        trade.reload

        expect(trade.status).to eq('EXIT')
        expect(trade.preview).to eq(false)
      end

      it 'restores order state if present' do
        trade.reload

        expect(trade.order_id).to eq('order-123')
        expect(trade.order_status).to eq('FILLED')
        expect(trade.order_instruction).to eq(:exit)
        expect(trade.order_price).to eq(1.50)
      end

      it 'returns self' do
        result = trade.reload
        expect(result).to eq(trade)
      end
    end

    context 'when no latest trade exists' do
      before do
        allow(mock_journal).to receive(:load_trade).and_return(nil)
      end

      it 'returns self without changes' do
        original_status = trade.status
        result = trade.reload

        expect(result).to eq(trade)
        expect(trade.status).to eq(original_status)
      end
    end
  end

  describe '#history' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }
    let(:history_data) { [double('Trade1'), double('Trade2')] }

    it 'delegates to journal trade_history' do
      expect(mock_journal).to receive(:trade_history).and_return(history_data)

      result = trade.history
      expect(result).to eq(history_data)
    end
  end

  describe '#delete' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }

    it 'delegates to journal delete_trade' do
      expect(mock_journal).to receive(:delete_trade)
      trade.delete
    end
  end

  describe '#current_file_path' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }

    it 'delegates to journal current_file_path' do
      expect(mock_journal).to receive(:current_file_path).and_return('/path/to/trade.json')

      result = trade.current_file_path
      expect(result).to eq('/path/to/trade.json')
    end
  end

  describe '#check_progress' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }

    it 'saves after checking progress' do
      expect(mock_journal).to receive(:save_trade).with(trade)
      trade.check_progress
    end
  end

  describe 'status helper methods' do
    describe '#open?' do
      it 'returns true for OPEN status' do
        trade = described_class.new(strategy: mock_strategy, status: 'OPEN')
        expect(trade.open?).to be true
      end

      it 'returns true for PREVIEW_OPEN status' do
        trade = described_class.new(strategy: mock_strategy, status: 'PREVIEW_OPEN')
        expect(trade.open?).to be true
      end

      it 'returns false for EXIT status' do
        trade = described_class.new(strategy: mock_strategy, status: 'EXIT')
        expect(trade.open?).to be false
      end
    end

    describe '#closed?' do
      it 'returns true for EXIT status' do
        trade = described_class.new(strategy: mock_strategy, status: 'EXIT')
        expect(trade.closed?).to be true
      end

      it 'returns true for PREVIEW_EXIT status' do
        trade = described_class.new(strategy: mock_strategy, status: 'PREVIEW_EXIT')
        expect(trade.closed?).to be true
      end

      it 'returns true for ERROR status' do
        trade = described_class.new(strategy: mock_strategy, status: 'ERROR')
        expect(trade.closed?).to be true
      end

      it 'returns false for OPEN status' do
        trade = described_class.new(strategy: mock_strategy, status: 'OPEN')
        expect(trade.closed?).to be false
      end
    end
  end

  describe 'class methods for trade management' do
    let(:mock_open_trades) { [double('Trade1'), double('Trade2')] }
    let(:mock_closed_trades) { [double('Trade3')] }

    describe '.find_open_trades' do
      it 'delegates to TradeJournal.load_open_trades' do
        expect(Platypi::TradeJournal).to receive(:load_open_trades).and_return(mock_open_trades)

        result = described_class.find_open_trades
        expect(result).to eq(mock_open_trades)
      end
    end

    describe '.find_closed_trades' do
      it 'delegates to TradeJournal.load_closed_trades' do
        expect(Platypi::TradeJournal).to receive(:load_closed_trades).and_return(mock_closed_trades)

        result = described_class.find_closed_trades
        expect(result).to eq(mock_closed_trades)
      end
    end

    describe '.find_trade' do
      let(:found_trade) { double('Trade') }

      it 'delegates to TradeJournal.load_trade' do
        expect(Platypi::TradeJournal).to receive(:load_trade).with('test-id').and_return(found_trade)

        result = described_class.find_trade('test-id')
        expect(result).to eq(found_trade)
      end
    end

    describe '.trade_open?' do
      it 'delegates to TradeJournal.trade_open?' do
        expect(Platypi::TradeJournal).to receive(:trade_open?).with('test-id').and_return(true)

        result = described_class.trade_open?('test-id')
        expect(result).to be true
      end
    end

    describe '.open_trade_count' do
      it 'delegates to TradeJournal.open_trade_count' do
        expect(Platypi::TradeJournal).to receive(:open_trade_count).and_return(3)

        result = described_class.open_trade_count
        expect(result).to eq(3)
      end
    end
  end

  describe '#open_state' do
    let(:trade) { described_class.new(strategy: mock_strategy, trade_id: trade_id) }
    let(:mock_open_state) { double('OpenState', status: 'OPEN', order_price: 1.50) }

    it 'delegates to journal open_state' do
      expect(mock_journal).to receive(:open_state).and_return(mock_open_state)

      result = trade.open_state
      expect(result).to eq(mock_open_state)
    end

    it 'returns nil when no open state exists' do
      expect(mock_journal).to receive(:open_state).and_return(nil)

      result = trade.open_state
      expect(result).to be_nil
    end
  end

  # ...existing test contexts for to_h, serialization, etc...

  describe '#to_h' do
    context 'when trade is in preview mode' do
      let(:trade) do
        described_class.new(
          strategy: mock_strategy,
          trade_id: trade_id,
          status: Platypi::Trades::TRADE_STATUSES[:preview_open],
          preview: true
        )
      end

      let(:expected_order) do
        {
          order_id: 'preview123',
          order_instruction: :open,
          order_status: 'ACCEPTED',
          order_price: 1.25,
          order_fees: 1.14,
          order_commission: 1.30,
          order_datetime: Time.now,
          order_rejects: []
        }
      end

      before do
        allow(trade).to receive(:order_to_h).and_return(expected_order)
      end

      it 'returns hash with order data' do
        freeze_time = Time.now.utc
        allow(Time).to receive(:now).and_return(freeze_time)

        result = trade.to_h

        expect(result).to be_a(Hash)
        expect(result[:trade_id]).to eq(trade_id)
        expect(result[:trade_status]).to eq(Platypi::Trades::TRADE_STATUSES[:preview_open])
        expect(result[:preview]).to eq(true)
        expect(result[:strategy]).to eq(mock_strategy.to_h)
        expect(result[:order]).to eq(expected_order)
        expect(result[:timestamp]).to eq(freeze_time)
      end

      it 'calls order_to_h for preview trades' do
        expect(trade).to receive(:order_to_h).and_return(expected_order)
        trade.to_h
      end
    end

    context 'when trade is not in preview mode' do
      let(:trade) do
        described_class.new(
          strategy: mock_strategy,
          trade_id: trade_id,
          status: Platypi::Trades::TRADE_STATUSES[:open],
          preview: false
        )
      end

      let(:expected_order) do
        {
          order_id: 'order123',
          order_instruction: :open,
          order_status: 'FILLED',
          order_price: 1.25,
          order_fees: 1.14,
          order_commission: 1.30,
          order_datetime: Time.now,
          order_rejects: []
        }
      end

      before do
        allow(trade).to receive(:order_to_h).and_return(expected_order)
      end

      it 'returns hash with actual order data' do
        freeze_time = Time.now.utc
        allow(Time).to receive(:now).and_return(freeze_time)

        result = trade.to_h

        expect(result).to be_a(Hash)
        expect(result[:trade_id]).to eq(trade_id)
        expect(result[:trade_status]).to eq(Platypi::Trades::TRADE_STATUSES[:open])
        expect(result[:preview]).to eq(false)
        expect(result[:strategy]).to eq(mock_strategy.to_h)
        expect(result[:order]).to eq(expected_order)
        expect(result[:timestamp]).to eq(freeze_time)
      end

      it 'calls order_to_h when preview is false' do
        expect(trade).to receive(:order_to_h).and_return(expected_order)
        trade.to_h
      end
    end

    context 'with different trade statuses' do
      let(:trade) do
        described_class.new(
          strategy: mock_strategy,
          trade_id: trade_id,
          status: Platypi::Trades::TRADE_STATUSES[:exit],
          preview: false
        )
      end

      before do
        allow(trade).to receive(:order_to_h).and_return({})
      end

      it 'includes the correct status in the hash' do
        result = trade.to_h
        expect(result[:trade_status]).to eq(Platypi::Trades::TRADE_STATUSES[:exit])
      end
    end

    context 'with custom trade_id' do
      let(:custom_trade_id) { 'custom-trade-123' }
      let(:trade) do
        described_class.new(
          strategy: mock_strategy,
          trade_id: custom_trade_id,
          status: status,
          preview: false
        )
      end

      before do
        allow(trade).to receive(:order_to_h).and_return({})
      end

      it 'includes the custom trade_id in the hash' do
        result = trade.to_h
        expect(result[:trade_id]).to eq(custom_trade_id)
      end
    end

    context 'when strategy returns different data' do
      let(:complex_strategy_data) do
        {
          type: 'ironcondor',
          quantity: 2,
          underlying_symbol: 'SPX',
          put_spread: {
            short_leg: { symbol: 'SPX250620P04800000', strike: 4800.0 },
            long_leg: { symbol: 'SPX250620P04790000', strike: 4790.0 }
          },
          call_spread: {
            short_leg: { symbol: 'SPX250620C05200000', strike: 5200.0 },
            long_leg: { symbol: 'SPX250620C05210000', strike: 5210.0 }
          }
        }
      end

      let(:complex_strategy) { double('ComplexStrategy', to_h: complex_strategy_data) }
      let(:trade) do
        described_class.new(
          strategy: complex_strategy,
          trade_id: trade_id,
          status: status,
          preview: false
        )
      end

      before do
        allow(trade).to receive(:order_to_h).and_return({})
      end

      it 'includes the complex strategy data in the hash' do
        result = trade.to_h
        expect(result[:strategy]).to eq(complex_strategy_data)
      end
    end

    context 'timestamp behavior' do
      let(:trade) do
        described_class.new(
          strategy: mock_strategy,
          trade_id: trade_id,
          status: status,
          preview: false
        )
      end

      before do
        allow(trade).to receive(:order_to_h).and_return({})
      end

      it 'generates a new timestamp each time to_h is called' do
        first_time = Time.parse('2023-01-01 12:00:00 UTC')
        second_time = Time.parse('2023-01-01 12:01:00 UTC')

        allow(Time).to receive(:now).and_return(first_time, second_time)

        first_result = trade.to_h
        second_result = trade.to_h

        expect(first_result[:timestamp]).to eq(first_time)
        expect(second_result[:timestamp]).to eq(second_time)
      end
    end
  end

  describe 'serialization' do
    let(:call_spread_strategy) do
      call_spread = Platypi::CallSpread.new(
        underlying_symbol: 'SPY',
        quantity: 2
      )

      # Mock the legs
      short_leg = double('CallOption',
        symbol: 'SPY250620C00500000',
        strike: 500.0,
        delta: 0.30,
        mark: 3.50,
        ask: 3.55,
        bid: 3.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1500
      )

      long_leg = double('CallOption',
        symbol: 'SPY250620C00510000',
        strike: 510.0,
        delta: 0.20,
        mark: 2.00,
        ask: 2.05,
        bid: 1.95,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 800
      )

      allow(call_spread).to receive(:short_leg).and_return(short_leg)
      allow(call_spread).to receive(:long_leg).and_return(long_leg)

      call_spread
    end

    let(:trade_with_strategy) do
      described_class.new(
        strategy: call_spread_strategy,
        trade_id: 'test-trade-123',
        status: 'OPEN',
        preview: false
      )
    end

    let(:sample_trade_hash) do
      {
        trade_id: 'test-trade-456',
        trade_status: Platypi::Trades::TRADE_STATUSES[:exit],
        preview: false,
        strategy: {
          type: 'callspread',
          quantity: 1,
          underlying_symbol: 'SPX',
          round: 2,
          increment: 0.01,
          short_leg: {
            symbol: 'SPX250620C05000000',
            strike: 5000.0,
            delta: 0.35,
            mark: 10.50,
            ask: 10.60,
            bid: 10.40,
            expiration_date: Date.new(2025, 6, 20),
            open_interest: 2000
          },
          long_leg: {
            symbol: 'SPX250620C05100000',
            strike: 5100.0,
            delta: 0.25,
            mark: 5.75,
            ask: 5.85,
            bid: 5.65,
            expiration_date: Date.new(2025, 6, 20),
            open_interest: 1200
          }
        },
        order: {
          order_id: 'order-789',
          order_instruction: :open,
          order_status: 'FILLED',
          order_price: 4.75,
          order_fees: 2.30,
          order_commission: 0.0,
          order_datetime: DateTime.parse('2025-06-19T10:30:00Z'),
          order_rejects: []
        },
        timestamp: Time.parse('2025-06-19T10:35:00Z')
      }
    end

    describe '#to_json' do
      before do
        allow(trade_with_strategy).to receive(:order_to_h).and_return({
          order_id: 'order-123',
          order_instruction: :open,
          order_status: 'WORKING',
          order_price: 1.50,
          order_fees: 1.14,
          order_commission: 1.30,
          order_datetime: DateTime.now,
          order_rejects: []
        })
      end

      it 'converts trade to JSON string' do
        json_string = trade_with_strategy.to_json
        expect(json_string).to be_a(String)

        parsed = JSON.parse(json_string, symbolize_names: true)
        expect(parsed[:trade_id]).to eq('test-trade-123')
        expect(parsed[:trade_status]).to eq('OPEN')
        expect(parsed[:strategy][:type]).to eq('callspread')
      end

      it 'includes all required fields in JSON' do
        json_string = trade_with_strategy.to_json
        parsed = JSON.parse(json_string, symbolize_names: true)

        expect(parsed).to have_key(:trade_id)
        expect(parsed).to have_key(:trade_status)
        expect(parsed).to have_key(:preview)
        expect(parsed).to have_key(:strategy)
        expect(parsed).to have_key(:order)
        expect(parsed).to have_key(:timestamp)
      end
    end

    describe '.from_hash' do
      it 'reconstructs Trade from hash with call spread strategy' do
        trade = described_class.from_hash(sample_trade_hash)

        expect(trade).to be_a(described_class)
        expect(trade.trade_id).to eq('test-trade-456')
        expect(trade.status).to eq(Platypi::Trades::TRADE_STATUSES[:exit])
        expect(trade.preview).to eq(false)
      end

      it 'reconstructs the strategy correctly' do
        trade = described_class.from_hash(sample_trade_hash)
        strategy = trade.instance_variable_get(:@strategy)

        expect(strategy).to be_a(Platypi::CallSpread)
        expect(strategy.underlying_symbol).to eq('SPX')
        expect(strategy.quantity).to eq(1)
        expect(strategy.short_leg.symbol).to eq('SPX250620C05000000')
        expect(strategy.long_leg.symbol).to eq('SPX250620C05100000')
      end

      it 'restores orderable state' do
        trade = described_class.from_hash(sample_trade_hash)

        expect(trade.order_id).to eq('order-789')
        expect(trade.order_status).to eq('FILLED')
        expect(trade.order_instruction).to eq(:open)
        expect(trade.order_price).to eq(4.75)
        expect(trade.order_fees).to eq(2.30)
        expect(trade.order_commission).to eq(0.0)
      end

      it 'handles missing strategy gracefully' do
        hash_without_strategy = sample_trade_hash.dup
        hash_without_strategy.delete(:strategy)

        trade = described_class.from_hash(hash_without_strategy)
        expect(trade.instance_variable_get(:@strategy)).to be_nil
      end

      it 'handles missing order data gracefully' do
        hash_without_order = sample_trade_hash.dup
        hash_without_order.delete(:order)

        trade = described_class.from_hash(hash_without_order)
        expect(trade.order_id).to be_nil
        expect(trade.order_status).to eq('UNKNOWN')
      end

      context 'with put spread strategy' do
        let(:put_spread_hash) do
          sample_trade_hash.merge(
            strategy: {
              type: 'putspread',
              quantity: 3,
              underlying_symbol: 'SPY',
              round: 2,
              increment: 0.01,
              short_leg: {
                symbol: 'SPY250620P00450000',
                strike: 450.0,
                delta: -0.25,
                mark: 2.75,
                ask: 2.80,
                bid: 2.70,
                expiration_date: Date.new(2025, 6, 20),
                open_interest: 1200
              },
              long_leg: {
                symbol: 'SPY250620P00440000',
                strike: 440.0,
                delta: -0.15,
                mark: 1.50,
                ask: 1.55,
                bid: 1.45,
                expiration_date: Date.new(2025, 6, 20),
                open_interest: 900
              }
            }
          )
        end

        it 'reconstructs put spread strategy correctly' do
          trade = described_class.from_hash(put_spread_hash)
          strategy = trade.instance_variable_get(:@strategy)

          expect(strategy).to be_a(Platypi::PutSpread)
          expect(strategy.underlying_symbol).to eq('SPY')
          expect(strategy.quantity).to eq(3)
        end
      end

      context 'with iron condor strategy' do
        let(:iron_condor_hash) do
          sample_trade_hash.merge(
            strategy: {
              type: 'ironcondor',
              quantity: 1,
              underlying_symbol: 'SPX',
              round: 2,
              increment: 0.01,
              put_spread: {
                type: 'putspread',
                short_leg: { symbol: 'SPX250620P04800000', strike: 4800.0 },
                long_leg: { symbol: 'SPX250620P04790000', strike: 4790.0 }
              },
              call_spread: {
                type: 'callspread',
                short_leg: { symbol: 'SPX250620C05200000', strike: 5200.0 },
                long_leg: { symbol: 'SPX250620C05210000', strike: 5210.0 }
              }
            }
          )
        end

        it 'reconstructs iron condor strategy correctly' do
          trade = described_class.from_hash(iron_condor_hash)
          strategy = trade.instance_variable_get(:@strategy)

          expect(strategy).to be_a(Platypi::IronCondor)
          expect(strategy.underlying_symbol).to eq('SPX')
          expect(strategy.quantity).to eq(1)
        end
      end
    end

    describe '.from_json' do
      it 'reconstructs Trade from JSON string' do
        json_string = sample_trade_hash.to_json
        trade = described_class.from_json(json_string)

        expect(trade).to be_a(described_class)
        expect(trade.trade_id).to eq('test-trade-456')
        expect(trade.status).to eq(Platypi::Trades::TRADE_STATUSES[:exit])
      end

      it 'handles malformed JSON gracefully' do
        expect {
          described_class.from_json('{"invalid": json}')
        }.to raise_error(JSON::ParserError)
      end
    end

    describe 'round-trip serialization' do
      before do
        allow(trade_with_strategy).to receive(:order_to_h).and_return({
          order_id: 'round-trip-test',
          order_instruction: :exit,
          order_status: 'FILLED',
          order_price: 0.75,
          order_fees: 1.14,
          order_commission: 1.30,
          order_datetime: DateTime.parse('2025-06-19T15:30:00Z'),
          order_rejects: []
        })
      end

      it 'preserves data through to_json -> from_json cycle' do
        original_hash = trade_with_strategy.to_h
        json_string = trade_with_strategy.to_json
        reconstructed_trade = described_class.from_json(json_string)

        expect(reconstructed_trade.trade_id).to eq(trade_with_strategy.trade_id)
        expect(reconstructed_trade.status).to eq(trade_with_strategy.status)
        expect(reconstructed_trade.preview).to eq(trade_with_strategy.preview)
      end

      it 'preserves strategy data through serialization cycle' do
        json_string = trade_with_strategy.to_json
        reconstructed_trade = described_class.from_json(json_string)
        reconstructed_strategy = reconstructed_trade.instance_variable_get(:@strategy)

        expect(reconstructed_strategy.underlying_symbol).to eq(call_spread_strategy.underlying_symbol)
        expect(reconstructed_strategy.quantity).to eq(call_spread_strategy.quantity)
      end

      it 'preserves order data through serialization cycle' do
        json_string = trade_with_strategy.to_json
        reconstructed_trade = described_class.from_json(json_string)

        expect(reconstructed_trade.order_id).to eq('round-trip-test')
        expect(reconstructed_trade.order_instruction).to eq(:exit)
        expect(reconstructed_trade.order_status).to eq('FILLED')
        expect(reconstructed_trade.order_price).to eq(0.75)
      end
    end
  end
end
