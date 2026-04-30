require 'rspec'
require 'date'
require 'json'
require_relative '../../spx_1dte/trade'
require_relative '../../spx_1dte/trades_file_manager'
require_relative '../../spx_1dte/data_objects'

RSpec.describe Trade do
  let(:fixtures_path) { File.expand_path('../fixtures/trades.json', __dir__) }
  let(:temp_trades_file) { File.join(Dir.tmpdir, "test_trades_#{Time.now.to_i}.json") }

  before(:each) do
    # Copy fixtures to temp file for testing
    FileUtils.cp(fixtures_path, temp_trades_file)
    TradesFileManager.setup(temp_trades_file)
  end

  after(:each) do
    FileUtils.rm_f(temp_trades_file) if File.exist?(temp_trades_file)
  end

  describe '.open_trade' do
    it 'returns the open trade from the file manager' do
      open_trade = described_class.open_trade
      expect(open_trade).to be_a(Trade)
      expect(open_trade.status).to eq(Trade::OPEN_STATUS)
    end
  end

  describe '#initialize' do
    let(:trade_data) do
      json_data = File.read(fixtures_path)
      data = JSON.parse(json_data, symbolize_names: true)
      data[:trades].first
    end

    let(:trade) do
      TradesFileManager.instance.to_trade_object(trade_data)
    end

    it 'creates a trade with the correct attributes' do
      expect(trade.id).to eq(trade_data[:id])
      expect(trade.exit_prof_price).to eq(trade_data[:exit_prof_price])
      expect(trade.exit_loss_mult).to eq(trade_data[:exit_loss_mult])
      expect(trade.price_increment).to eq(trade_data[:price_increment])
    end

    it 'loads trade history from data' do
      expect(trade.trade_history).to be_an(Array)
      expect(trade.trade_history.length).to eq(trade_data[:trade_history].length)
      expect(trade.trade_history.first[:event_type]).to eq(trade_data[:trade_history].first[:event_type])
    end
  end

  describe 'trade history' do
    let(:init_strategy) do
      # Build a simple iron condor strategy
      call_short = OptionLeg.new(
        symbol: 'SPXW  251106C06860000',
        contract_type: 'CALL',
        strike: 6860.0,
        mark: 1.1,
        delta: 0.063,
        expiration_date: Date.new(2025, 11, 6),
        quantity: 1
      )

      call_long = OptionLeg.new(
        symbol: 'SPXW  251106C06880000',
        contract_type: 'CALL',
        strike: 6880.0,
        mark: 0.38,
        delta: 0.023,
        expiration_date: Date.new(2025, 11, 6),
        quantity: 1
      )

      put_short = OptionLeg.new(
        symbol: 'SPXW  251106P06695000',
        contract_type: 'PUT',
        strike: 6695.0,
        mark: 1.78,
        delta: -0.06,
        expiration_date: Date.new(2025, 11, 6),
        quantity: 1
      )

      put_long = OptionLeg.new(
        symbol: 'SPXW  251106P06675000',
        contract_type: 'PUT',
        strike: 6675.0,
        mark: 1.1,
        delta: -0.038,
        expiration_date: Date.new(2025, 11, 6),
        quantity: 1
      )

      call_spread = VerticalSpread.new(
        short_leg: call_short,
        long_leg: call_long,
        contract_type: 'CALL',
        quantity: 1,
        expiration_date: Date.new(2025, 11, 6)
      )

      put_spread = VerticalSpread.new(
        short_leg: put_short,
        long_leg: put_long,
        contract_type: 'PUT',
        quantity: 1,
        expiration_date: Date.new(2025, 11, 6)
      )

      IronCondor.new(
        put_spread: put_spread,
        call_spread: call_spread,
        quantity: 1,
        expiration_date: Date.new(2025, 11, 6),
        price_increment: 0.05
      )
    end

    it 'saves opening event and updates status' do
      trade = Trade.new(
        id: 'test-save',
        exit_prof_price: 0.5,
        exit_loss_mult: 3.0
      )

      expect(trade.status).to eq(Trade::NEW_STATUS)
      expect(trade.trade_history.length).to eq(0)

      trade.save_event(
        'OPEN_IRON_CONDOR',
        put_short_symbol: 'SPXW  251106P06695000',
        put_long_symbol: 'SPXW  251106P06675000',
        call_short_symbol: 'SPXW  251106C06860000',
        call_long_symbol: 'SPXW  251106C06880000',
        price: 1.35,
        quantity: 1,
        fees: 2.1,
        commissions: 2.6,
        credit_debit: :credit
      )

      expect(trade.trade_history.length).to eq(1)
      expect(trade.status).to eq(Trade::OPEN_STATUS)
      expect(trade.trade_history.first[:event_type]).to eq('OPEN_IRON_CONDOR')
      expect(trade.trade_history.first[:price]).to eq(1.35)
      expect(trade.trade_history.first[:credit_debit_amount]).to eq(135.0)
    end

    it 'saves closing event and updates status' do
      trade = Trade.new(
        id: 'test-close',
        exit_prof_price: 0.5,
        exit_loss_mult: 3.0
      )

      # Open the trade first
      trade.save_event(
        'OPEN_IRON_CONDOR',
        put_short_symbol: 'SPXW  251106P06695000',
        put_long_symbol: 'SPXW  251106P06675000',
        call_short_symbol: 'SPXW  251106C06860000',
        call_long_symbol: 'SPXW  251106C06880000',
        price: 1.35,
        quantity: 1,
        fees: 2.1,
        commissions: 2.6,
        credit_debit: :credit
      )

      expect(trade.status).to eq(Trade::OPEN_STATUS)

      # Close the trade
      trade.save_event(
        'CLOSE_IRON_CONDOR',
        put_short_symbol: 'SPXW  251106P06695000',
        put_long_symbol: 'SPXW  251106P06675000',
        call_short_symbol: 'SPXW  251106C06860000',
        call_long_symbol: 'SPXW  251106C06880000',
        price: 0.1,
        quantity: 1,
        fees: 2.1,
        commissions: 2.6,
        credit_debit: :debit
      )

      expect(trade.trade_history.length).to eq(2)
      expect(trade.status).to eq(Trade::CLOSED_STATUS)
      expect(trade.trade_history.last[:event_type]).to eq('CLOSE_IRON_CONDOR')
      expect(trade.trade_history.last[:credit_debit_amount]).to eq(-10.0)
    end
  end

  describe 'strategy detection' do
    let(:closed_trade_data) do
      json_data = File.read(fixtures_path)
      data = JSON.parse(json_data, symbolize_names: true)
      data[:trades].find { |t| t[:status] == 'CLOSED' }
    end

    let(:trade) do
      TradesFileManager.instance.to_trade_object(closed_trade_data)
    end

    it 'detects open iron condor strategy' do
      # Create trade with only opening event
      trade_with_open = Trade.new(
        id: closed_trade_data[:id],
        trade_history: [closed_trade_data[:trade_history].first.merge({ timestamp: Time.parse(closed_trade_data[:trade_history].first[:timestamp]) })]
      )
      expect(trade_with_open.strategy).to be_a(IronCondor)
    end

    it 'detects open call spread strategy' do
      # Create trade with opening IC event and then close the put spread
      open_event = closed_trade_data[:trade_history].first.merge({
        timestamp: Time.parse(closed_trade_data[:trade_history].first[:timestamp])
      })

      # Create a close put spread event
      close_put_event = {
        event_type: 'CLOSE_PUT_SPREAD',
        put_short_symbol: closed_trade_data[:put_spread][:short_leg][:symbol],
        put_long_symbol: closed_trade_data[:put_spread][:long_leg][:symbol],
        price: 0.05,
        quantity: 1.0,
        credit_debit_type: :debit,
        credit_debit_amount: -5.0,
        fees: 1.05,
        commissions: 1.3,
        timestamp: Time.parse(closed_trade_data[:trade_history].first[:timestamp]) + 3600 # 1 hour later
      }

      trade_with_call_spread = Trade.new(
        id: closed_trade_data[:id],
        trade_history: [open_event, close_put_event]
      )

      expect(trade_with_call_spread.strategy).to be_a(VerticalSpread)
      expect(trade_with_call_spread.strategy.contract_type).to eq('CALL')
    end

    it 'detects when position is closed' do
      expect(trade.position_closed?).to be true
    end

    it 'returns symbols for open positions' do
      trade_with_open = Trade.new(
        id: closed_trade_data[:id],
        trade_history: [closed_trade_data[:trade_history].first.merge({ timestamp: Time.parse(closed_trade_data[:trade_history].first[:timestamp]) })]
      )

      symbols = trade_with_open.symbols
      expect(symbols).to be_an(Array)
      expect(symbols.length).to eq(4) # Iron condor has 4 legs
    end
  end

  describe 'position management' do
    let(:trade_data) do
      json_data = File.read(fixtures_path)
      data = JSON.parse(json_data, symbolize_names: true)
      data[:trades].first
    end

    it 'tracks current positions after opening' do
      trade = Trade.new(
        id: trade_data[:id],
        trade_history: [trade_data[:trade_history].first.merge({ timestamp: Time.parse(trade_data[:trade_history].first[:timestamp]) })]
      )

      positions = trade.current_positions
      expect(positions).to have_key(:call_positions)
      expect(positions).to have_key(:put_positions)
      expect(positions[:call_positions]).not_to be_empty
      expect(positions[:put_positions]).not_to be_empty
    end

    it 'updates positions after closing' do
      trade = TradesFileManager.instance.to_trade_object(trade_data)

      positions = trade.current_positions
      # After both open and close events, all positions should be zero
      all_positions_closed = positions[:call_positions].all? { |_, qty| qty == 0 } &&
                             positions[:put_positions].all? { |_, qty| qty == 0 }
      expect(all_positions_closed).to be true
    end

    it 'tracks only call spread positions when put spread is closed' do
      # Create trade with opening IC event and then close the put spread
      open_event = trade_data[:trade_history].first.merge({
        timestamp: Time.parse(trade_data[:trade_history].first[:timestamp])
      })

      # Create a close put spread event
      close_put_event = {
        event_type: 'CLOSE_PUT_SPREAD',
        put_short_symbol: trade_data[:put_spread][:short_leg][:symbol],
        put_long_symbol: trade_data[:put_spread][:long_leg][:symbol],
        price: 0.05,
        quantity: 1.0,
        credit_debit_type: :debit,
        credit_debit_amount: -5.0,
        fees: 1.05,
        commissions: 1.3,
        timestamp: Time.parse(trade_data[:trade_history].first[:timestamp]) + 3600 # 1 hour later
      }

      trade = Trade.new(
        id: trade_data[:id],
        trade_history: [open_event, close_put_event]
      )

      positions = trade.current_positions

      # Put positions should be empty (closed)
      expect(positions[:put_positions]).to be_empty

      # Call positions should have the 2 call spread legs
      expect(positions[:call_positions]).not_to be_empty
      expect(positions[:call_positions].length).to eq(2)

      # Should have the call short and long symbols
      expect(positions[:call_positions]).to have_key(trade_data[:call_spread][:short_leg][:symbol])
      expect(positions[:call_positions]).to have_key(trade_data[:call_spread][:long_leg][:symbol])

      # Short leg should have negative quantity, long leg positive
      expect(positions[:call_positions][trade_data[:call_spread][:short_leg][:symbol]]).to be < 0
      expect(positions[:call_positions][trade_data[:call_spread][:long_leg][:symbol]]).to be > 0
    end
  end

  describe 'trade value calculations' do
    let(:trade_data) do
      json_data = File.read(fixtures_path)
      data = JSON.parse(json_data, symbolize_names: true)
      data[:trades].first
    end

    let(:trade) do
      TradesFileManager.instance.to_trade_object(trade_data)
    end

    it 'calculates profit_loss correctly' do
      expected_pl = trade_data[:total_credit_debit] - trade_data[:total_fees] - trade_data[:total_commissions]
      expect(trade.profit_loss).to eq(expected_pl)
    end

    it 'retrieves open_price from trade history' do
      expect(trade.open_price).to eq(trade_data[:open_price])
    end

    it 'calculates open_credit correctly' do
      expected_credit = (trade_data[:open_price] * trade_data[:quantity] * 100) -
                       trade_data[:open_fees] - trade_data[:open_commissions]
      expect(trade.open_credit).to eq(expected_credit)
    end

    it 'calculates target_profit_price' do
      target = trade.target_profit_price
      expect(target).to be_a(Numeric)
      expect(target).to be > 0
    end

    it 'calculates max_loss_price' do
      max_loss = trade.max_loss_price
      expect(max_loss).to be_a(Numeric)
      expect(max_loss).to be > trade.target_profit_price
    end
  end
end
