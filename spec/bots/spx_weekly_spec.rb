# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::SPXWeekly do
  let(:bot) { described_class.new(mode: :preview) }
  let(:live_bot) { described_class.new(mode: :live) }

  let(:mock_strategy) do
    double('IronCondor',
      call_spread: double(short_leg: double(strike: 5000), long_leg: double(strike: 5025)),
      put_spread: double(short_leg: double(strike: 4900), long_leg: double(strike: 4875)),
      credit: 150.0,
      'increment=': nil,
      check_market: nil,
      'market_change?': false
    )
  end

  let(:mock_trade) do
    double('Trade',
      trade_id: 'test-123',
      status: 'OPEN',
      preview: true,
      strategy: mock_strategy,
      open: nil,
      exit: nil,
      accepted?: true,
      filled?: false,
      working?: false,
      opening?: true,
      exiting?: false,
      check_order_status: nil,
      check_progress: 50.0,
      check_risk: 'GREEN',
      order_id: 'order-123',
      order_status: 'WORKING',
      order_rejects: [],
      stop_order: nil
    )
  end

  let(:mock_null_strategy) { instance_double('Platypi::NullStrategy') }
  let(:mock_finder) { instance_double('Platypi::IronCondorFinder') }

  describe '#initialize' do
    it 'sets default configuration for SPX options' do
      expect(bot.underlying_symbol).to eq('$SPX')
      expect(bot.option_root).to eq('SPXW')
      expect(bot.settlement_type).to eq('P')
      expect(bot.mode).to eq(:preview)
      expect(bot.sleep_interval).to eq(10)
    end

    it 'accepts custom mode' do
      expect(live_bot.mode).to eq(:live)
    end
  end

  describe '#run' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
    end

    context 'when there is an existing trade' do
      before do
        allow(bot).to receive(:find_current_trade).and_return(mock_trade)
        allow(bot).to receive(:handle_existing_trade)
        # Stop after one iteration
        allow(bot).to receive(:handle_existing_trade) do
          bot.instance_variable_set(:@running, false)
        end
      end

      it 'handles the existing trade' do
        bot.run
        expect(bot).to have_received(:handle_existing_trade).with(mock_trade)
      end
    end

    context 'when there is no existing trade' do
      before do
        allow(bot).to receive(:find_current_trade).and_return(nil)
        allow(bot).to receive(:attempt_new_trade)
        # Stop after one iteration
        allow(bot).to receive(:attempt_new_trade) do
          bot.instance_variable_set(:@running, false)
        end
      end

      it 'attempts to create a new trade' do
        bot.run
        expect(bot).to have_received(:attempt_new_trade)
      end
    end

    context 'when an exception occurs' do
      before do
        allow(bot).to receive(:find_current_trade).and_raise(StandardError, 'Test error')
        call_count = 0
        allow(bot).to receive(:sleep) do
          call_count += 1
          bot.instance_variable_set(:@running, false) if call_count >= 1
        end
      end

      it 'handles the error and continues' do
        bot.run
        expect(bot).to have_received(:sleep).at_least(:once)
      end
    end
  end

  describe '#stop' do
    it 'stops the bot' do
      bot.stop
      expect(bot.instance_variable_get(:@running)).to be false
    end
  end

  describe '#find_current_trade' do
    before do
      allow(Platypi::Trades::Trade).to receive(:find_open_trades).and_return([mock_trade])
    end

    it 'returns the first open trade' do
      result = bot.send(:find_current_trade)
      expect(result).to eq(mock_trade)
    end
  end

  describe '#handle_existing_trade' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
    end

    context 'with OPEN status and filled trade' do
      before do
        allow(mock_trade).to receive(:status).and_return('OPEN')
        allow(mock_trade).to receive(:filled?).and_return(true)
        allow(bot).to receive(:monitor_trade_until_exit)
      end

      it 'monitors the trade' do
        bot.send(:handle_existing_trade, mock_trade)
        expect(bot).to have_received(:monitor_trade_until_exit).with(mock_trade)
      end
    end

    context 'with PREVIEW_OPEN status' do
      before do
        allow(mock_trade).to receive(:status).and_return('PREVIEW_OPEN')
        allow(mock_trade).to receive(:preview).and_return(true)
        allow(bot).to receive(:monitor_trade_until_exit)
      end

      it 'monitors the preview trade' do
        bot.send(:handle_existing_trade, mock_trade)
        expect(bot).to have_received(:monitor_trade_until_exit).with(mock_trade)
      end
    end

    context 'with unfilled OPEN trade' do
      before do
        allow(mock_trade).to receive(:status).and_return('OPEN')
        allow(mock_trade).to receive(:filled?).and_return(false)
        allow(mock_trade).to receive(:preview).and_return(false)
        allow(bot).to receive(:wait_for_order_completion)
      end

      it 'waits for order completion' do
        bot.send(:handle_existing_trade, mock_trade)
        expect(bot).to have_received(:wait_for_order_completion).with(mock_trade)
      end
    end

    context 'with EXIT status and filled trade' do
      before do
        allow(mock_trade).to receive(:status).and_return('EXIT')
        allow(mock_trade).to receive(:filled?).and_return(true)
        allow(bot).to receive(:complete_trade)
      end

      it 'completes the trade' do
        bot.send(:handle_existing_trade, mock_trade)
        expect(bot).to have_received(:complete_trade).with(mock_trade)
      end
    end

    context 'with unknown trade status' do
      before do
        allow(mock_trade).to receive(:status).and_return('UNKNOWN')
      end

      it 'sleeps and logs unknown status' do
        bot.send(:handle_existing_trade, mock_trade)
        expect(bot).to have_received(:sleep).with(10)
      end
    end
  end

  describe '#attempt_new_trade' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
    end

    context 'when no strategy is found' do
      before do
        allow(bot).to receive(:find_trading_opportunity).and_return(nil)
      end

      it 'sleeps and returns' do
        bot.send(:attempt_new_trade)
        expect(bot).to have_received(:sleep)
      end
    end

    context 'when trade creation fails' do
      before do
        allow(bot).to receive(:find_trading_opportunity).and_return(mock_strategy)
        allow(bot).to receive(:create_trade).and_return(nil)
      end

      it 'sleeps and returns' do
        bot.send(:attempt_new_trade)
        expect(bot).to have_received(:sleep)
      end
    end

    context 'when order placement succeeds' do
      before do
        allow(bot).to receive(:find_trading_opportunity).and_return(mock_strategy)
        allow(bot).to receive(:create_trade).and_return(mock_trade)
        allow(bot).to receive(:place_opening_order).and_return(true)
      end

      it 'places the order successfully' do
        bot.send(:attempt_new_trade)
        expect(bot).to have_received(:place_opening_order).with(mock_trade)
      end
    end

    context 'when order placement fails' do
      before do
        allow(bot).to receive(:find_trading_opportunity).and_return(mock_strategy)
        allow(bot).to receive(:create_trade).and_return(mock_trade)
        allow(bot).to receive(:place_opening_order).and_return(false)
      end

      it 'sleeps and returns' do
        bot.send(:attempt_new_trade)
        expect(bot).to have_received(:sleep)
      end
    end
  end

  describe '#find_trading_opportunity' do
    let(:mock_opt_chain) { double('OptionChain') }
    let(:next_friday) { Date.today + 7 }

    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:next_weekday).and_return(next_friday)
      allow(Platypi::IronCondorFinder).to receive(:new).and_return(mock_finder)
    end

    context 'when finder returns null strategy' do
      before do
        allow(mock_finder).to receive(:search).and_return(mock_null_strategy)
        allow(mock_null_strategy).to receive(:is_a?).with(Platypi::NullStrategy).and_return(true)
      end

      it 'returns nil' do
        result = bot.send(:find_trading_opportunity)
        expect(result).to be_nil
      end
    end

    context 'when finder returns valid strategy' do
      before do
        allow(mock_finder).to receive(:search).and_return(mock_strategy)
        allow(mock_strategy).to receive(:is_a?).with(Platypi::NullStrategy).and_return(false)
      end

      it 'returns the strategy' do
        result = bot.send(:find_trading_opportunity)
        expect(result).to eq(mock_strategy)
      end

      it 'creates finder with correct parameters' do
        bot.send(:find_trading_opportunity)
        expect(Platypi::IronCondorFinder).to have_received(:new).with(
          underlying_symbol: '$SPX',
          expiration_date: next_friday,
          short_delta: 0.08,
          max_spread: 25.0,
          min_credit: 105.0,
          min_open_interest: 0,
          dist_from_strike: 0.01,
          settlement_type: 'P',
          option_root: 'SPXW'
        )
      end

      it 'calls finder search with option chain parameters' do
        bot.send(:find_trading_opportunity)
        expect(mock_finder).to have_received(:search).with(
          from_date: next_friday,
          to_date: next_friday
        )
      end
    end
  end

  describe '#create_trade' do
    before do
      allow(mock_strategy).to receive(:increment=).with(0.05)
      allow(mock_strategy).to receive(:check_market)
      allow(Platypi::Trades::Trade).to receive(:new).and_return(mock_trade)
    end

    it 'sets up strategy and creates trade' do
      result = bot.send(:create_trade, mock_strategy)

      expect(mock_strategy).to have_received(:increment=).with(0.05)
      expect(mock_strategy).to have_received(:check_market)
      expect(Platypi::Trades::Trade).to have_received(:new).with(
        strategy: mock_strategy,
        preview: true
      )
      expect(result).to eq(mock_trade)
    end

    context 'in live mode' do
      it 'creates trade with preview false' do
        live_bot.send(:create_trade, mock_strategy)
        expect(Platypi::Trades::Trade).to have_received(:new).with(
          strategy: mock_strategy,
          preview: false
        )
      end
    end

    context 'when an error occurs' do
      before do
        allow(bot).to receive(:puts)
        allow(Platypi::Trades::Trade).to receive(:new).and_raise(StandardError, 'Test error')
      end

      it 'returns nil' do
        result = bot.send(:create_trade, mock_strategy)
        expect(result).to be_nil
      end
    end
  end

  describe '#place_opening_order' do
    before do
      allow(bot).to receive(:puts)
    end

    context 'in preview mode with accepted order' do
      before do
        allow(mock_trade).to receive(:preview).and_return(true)
        allow(mock_trade).to receive(:accepted?).and_return(true)
      end

      it 'returns true' do
        result = bot.send(:place_opening_order, mock_trade)
        expect(result).to be true
      end
    end

    context 'in preview mode with rejected order' do
      before do
        allow(mock_trade).to receive(:preview).and_return(true)
        allow(mock_trade).to receive(:accepted?).and_return(false)
        allow(mock_trade).to receive(:order_rejects).and_return(['Invalid price'])
      end

      it 'returns false' do
        result = bot.send(:place_opening_order, mock_trade)
        expect(result).to be false
      end
    end

    context 'in live mode' do
      before do
        allow(mock_trade).to receive(:preview).and_return(false)
        allow(mock_trade).to receive(:order_id).and_return('order-123')
      end

      it 'returns true' do
        result = bot.send(:place_opening_order, mock_trade)
        expect(result).to be true
      end
    end

    context 'when an error occurs' do
      before do
        allow(mock_trade).to receive(:open).and_raise(StandardError, 'Test error')
      end

      it 'returns false' do
        result = bot.send(:place_opening_order, mock_trade)
        expect(result).to be false
      end
    end
  end

  describe '#wait_for_order_completion' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
      allow(Time).to receive(:now).and_return(Time.new(2025, 6, 20, 10, 0, 0))
    end

    context 'in preview mode' do
      before do
        allow(mock_trade).to receive(:preview).and_return(true)
      end

      it 'returns immediately' do
        bot.send(:wait_for_order_completion, mock_trade)
        expect(mock_trade).not_to have_received(:check_order_status)
      end
    end

    context 'when order is filled quickly' do
      before do
        allow(mock_trade).to receive(:preview).and_return(false)
        allow(mock_trade).to receive(:filled?).and_return(true)
        allow(mock_trade).to receive(:opening?).and_return(true)
        allow(mock_trade).to receive(:order_id).and_return('order-123')
      end

      it 'returns when filled' do
        bot.send(:wait_for_order_completion, mock_trade)
        expect(bot).to have_received(:puts).with("Entry order filled! ID: order-123")
      end
    end

    context 'when market conditions change during entry' do
      before do
        allow(mock_trade).to receive(:preview).and_return(false)
        allow(mock_trade).to receive(:filled?).and_return(false)
        allow(mock_trade).to receive(:working?).and_return(false)
        allow(mock_trade).to receive(:opening?).and_return(true)
        allow(mock_strategy).to receive(:market_change?).and_return(true)
      end

      it 'stops the order' do
        bot.send(:wait_for_order_completion, mock_trade)
        expect(mock_trade).to have_received(:stop_order)
      end
    end

    context 'when order times out on entry' do
      before do
        start_time = Time.new(2025, 6, 20, 10, 0, 0)
        timeout_time = Time.new(2025, 6, 20, 10, 6, 0) # 6 minutes later

        allow(Time).to receive(:now).and_return(start_time, timeout_time)
        allow(mock_trade).to receive(:preview).and_return(false)
        allow(mock_trade).to receive(:filled?).and_return(false)
        allow(mock_trade).to receive(:working?).and_return(false)
        allow(mock_trade).to receive(:opening?).and_return(true)
        allow(mock_strategy).to receive(:market_change?).and_return(false)
      end

      it 'cancels the order' do
        bot.send(:wait_for_order_completion, mock_trade)
        expect(mock_trade).to have_received(:stop_order)
      end
    end
  end

  describe '#monitor_trade_until_exit' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
      allow(mock_trade).to receive(:check_progress).and_return(50.0)
      allow(mock_trade).to receive(:check_risk).and_return('GREEN')
    end

    context 'when progress is nil' do
      before do
        allow(mock_trade).to receive(:check_progress).and_return(nil)
      end

      it 'sleeps and returns' do
        bot.send(:monitor_trade_until_exit, mock_trade)
        expect(bot).to have_received(:sleep)
      end
    end

    context 'when profit target is reached' do
      before do
        allow(mock_trade).to receive(:check_progress).and_return(100.0)
        allow(bot).to receive(:place_exit_order)
      end

      it 'places exit order' do
        bot.send(:monitor_trade_until_exit, mock_trade)
        expect(bot).to have_received(:place_exit_order).with(mock_trade)
      end
    end

    context 'when stop loss is triggered' do
      before do
        allow(mock_trade).to receive(:check_progress).and_return(-100.0)
        allow(bot).to receive(:place_exit_order)
      end

      it 'places exit order' do
        bot.send(:monitor_trade_until_exit, mock_trade)
        expect(bot).to have_received(:place_exit_order).with(mock_trade)
      end
    end

    context 'when risk is RED' do
      before do
        allow(mock_trade).to receive(:check_risk).and_return('RED')
      end

      it 'stops the bot' do
        bot.send(:monitor_trade_until_exit, mock_trade)
        expect(bot.instance_variable_get(:@running)).to be false
      end
    end

    context 'when trade is progressing normally' do
      it 'sleeps and continues' do
        bot.send(:monitor_trade_until_exit, mock_trade)
        expect(bot).to have_received(:sleep)
      end
    end
  end

  describe '#place_exit_order' do
    before do
      allow(bot).to receive(:puts)
      allow(mock_strategy).to receive(:check_market)
      allow(mock_strategy).to receive(:increment=)
    end

    context 'in preview mode' do
      before do
        allow(mock_trade).to receive(:preview).and_return(true)
      end

      it 'creates preview exit order' do
        bot.send(:place_exit_order, mock_trade)
        expect(bot).to have_received(:puts).with("Preview exit order created")
      end
    end

    context 'in live mode' do
      before do
        allow(mock_trade).to receive(:preview).and_return(false)
      end

      it 'places live exit order' do
        bot.send(:place_exit_order, mock_trade)
        expect(bot).to have_received(:puts).with("Exit order placed")
      end
    end

    context 'when an error occurs' do
      before do
        allow(mock_trade).to receive(:exit).and_raise(StandardError, 'Exit error')
      end

      it 'handles the error gracefully' do
        bot.send(:place_exit_order, mock_trade)
        expect(bot).to have_received(:puts).with("Error placing exit order: Exit error")
      end
    end
  end

  describe '#complete_trade' do
    before do
      allow(bot).to receive(:puts)
      allow(bot).to receive(:sleep)
    end

    it 'logs completion and sleeps' do
      bot.send(:complete_trade, mock_trade)
      expect(bot).to have_received(:puts).with("Trade test-123 completed successfully")
      expect(bot).to have_received(:sleep).with(10)
    end
  end

  describe '#next_weekday' do
    context 'when next week falls on Saturday' do
      before do
        allow(Date).to receive(:today).and_return(Date.new(2025, 6, 13)) # Friday
        # Date.today + 7 would be Friday, June 20
        # We want to test Saturday case
        saturday = Date.new(2025, 6, 14) # Saturday
        allow(bot).to receive(:next_weekday).and_call_original
        allow(Date.today + 7).to receive(:wday).and_return(6) # Saturday
      end

      it 'returns a Date object' do
        result = bot.send(:next_weekday)
        expect(result).to be_a(Date)
      end
    end

    context 'when next week falls on Sunday' do
      before do
        allow(Date).to receive(:today).and_return(Date.new(2025, 6, 14)) # Saturday
      end

      it 'returns the following Monday' do
        result = bot.send(:next_weekday)
        expect(result.wday).not_to eq(0) # Not Sunday
      end
    end

    context 'when next week falls on a weekday' do
      before do
        allow(Date).to receive(:today).and_return(Date.new(2025, 6, 13)) # Friday
      end

      it 'returns the same date' do
        result = bot.send(:next_weekday)
        expected_date = Date.new(2025, 6, 20) # Friday + 7 days
        expect(result).to eq(expected_date)
      end
    end
  end
end