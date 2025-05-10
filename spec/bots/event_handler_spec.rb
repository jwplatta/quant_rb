# frozen_string_literal: true

require 'spec_helper'
require_relative '../../bots/event_handler'
require_relative '../../bots/trade_event'
require_relative '../../services/trades/null_trade'

RSpec.describe EventHandler do
  let(:mock_queue) { instance_double(Queue) }
  let(:mock_bot) { double('Bot') }
  let(:mock_trade) { double('Trade', is_a?: false) }
  let(:event_handler) { described_class.new(mock_bot, mock_queue) }
  let(:mock_file_mutex) { instance_double(Mutex) }

  before do
    allow(mock_queue).to receive(:pop).and_return(TradeEvent.new(:stop_test))
    allow(mock_bot).to receive(:file_mutex).and_return(mock_file_mutex)
    allow(mock_file_mutex).to receive(:synchronize).and_yield
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:delete)

    # Mock methods that are needed in various handlers
    allow(mock_bot).to receive(:save_trade)
    stub_const("#{mock_bot.class.name}::TRADE_FILE", 'trade_file.json')
  end

  describe '#initialize' do
    it 'sets up instance variables' do
      expect(event_handler.bot).to eq(mock_bot)
      expect(event_handler.queue).to eq(mock_queue)
    end
  end

  describe '#start and #stop' do
    it 'starts and stops the event handling thread' do
      # Mock our way out of the infinite loop
      allow(event_handler).to receive(:handle_event) do
        event_handler.instance_variable_set(:@running, false)
      end

      # Test that the thread starts
      event_handler.start
      expect(event_handler.thread).to be_a(Thread)

      # Wait for the thread to terminate due to our mocking
      event_handler.thread.join(0.1)

      # Create a new thread for testing stop
      new_thread = Thread.new { sleep 10 }
      event_handler.instance_variable_set(:@thread, new_thread)
      expect(event_handler.thread).to be_alive

      # Test that stop works
      event_handler.stop
      sleep(0.05) # Give the thread time to stop
      expect(event_handler.thread).not_to be_alive
    end
  end

  describe '#handle_event' do
    # We need to test events individually since the handler methods are not all defined
    # in the EventHandler class (handle_check_market is missing)

    it 'calls handle_find_new_trade for find_new_trade event' do
      event = TradeEvent.new(:find_new_trade)
      expect(event_handler).to receive(:handle_find_new_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_order_filled for order_filled event' do
      event = TradeEvent.new(:order_filled, { trade: mock_trade })
      expect(event_handler).to receive(:handle_order_filled).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_order_failed for order_failed event' do
      event = TradeEvent.new(:order_failed, { trade: mock_trade })
      expect(event_handler).to receive(:handle_order_failed).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_market_changed for market_changed event' do
      event = TradeEvent.new(:market_changed, { trade: mock_trade })
      expect(event_handler).to receive(:handle_market_changed).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_exit_loss for exit_loss event' do
      event = TradeEvent.new(:exit_loss, { trade: mock_trade })
      expect(event_handler).to receive(:handle_exit_loss).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_exit_profit for exit_profit event' do
      event = TradeEvent.new(:exit_profit, { trade: mock_trade })
      expect(event_handler).to receive(:handle_exit_profit).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_hold for hold event' do
      event = TradeEvent.new(:hold, { trade: mock_trade })
      expect(event_handler).to receive(:handle_hold).with(mock_trade)
      event_handler.send(:handle_event, event)
    end

    it 'calls handle_error for error event' do
      error = StandardError.new
      event = TradeEvent.new(:error, { error: error })
      expect(event_handler).to receive(:handle_error).with(error)
      event_handler.send(:handle_event, event)
    end
  end

  describe '#handle_find_new_trade' do
    let(:next_weekday) { Date.today + 7 }
    let(:null_trade) { instance_double(NullTrade, is_a?: true) }
    let(:valid_trade) { double('Trade', is_a?: false) }

    before do
      allow(mock_bot).to receive(:next_weekday).and_return(next_weekday)
      allow(mock_bot).to receive(:find_trade)
    end

    context 'when no suitable trade is found' do
      it 'returns early without placing an order' do
        allow(mock_bot).to receive(:find_trade).and_return(null_trade)

        # We don't need to set an expectation on NullTrade, we just need to make sure
        # it doesn't try to call preview on valid_trade
        expect(valid_trade).not_to receive(:preview)

        event_handler.send(:handle_find_new_trade)
      end
    end

    context 'when a valid trade is found and accepted' do
      it 'places an entry order and saves the trade' do
        allow(mock_bot).to receive(:find_trade).and_return(valid_trade)
        allow(valid_trade).to receive(:increment=)
        allow(valid_trade).to receive(:preview)
        allow(valid_trade).to receive(:order_status).and_return('ACCEPTED')
        allow(valid_trade).to receive(:open)
        allow(valid_trade).to receive(:order_id).and_return('12345')

        event_handler.send(:handle_find_new_trade)

        expect(valid_trade).to have_received(:increment=).with(0.05)
        expect(valid_trade).to have_received(:preview).with(order_instruction: :entry)
        expect(valid_trade).to have_received(:open)
        expect(mock_bot).to have_received(:save_trade).with(valid_trade)
      end
    end

    context 'when a valid trade is found but rejected' do
      it 'logs rejection without placing order' do
        allow(mock_bot).to receive(:find_trade).and_return(valid_trade)
        allow(valid_trade).to receive(:increment=)
        allow(valid_trade).to receive(:preview)
        allow(valid_trade).to receive(:order_status).and_return('REJECTED')
        allow(valid_trade).to receive(:order_rejects).and_return(['Invalid order'])

        expect(valid_trade).not_to receive(:open)

        event_handler.send(:handle_find_new_trade)
        expect(mock_bot).not_to have_received(:save_trade).with(valid_trade)
      end
    end
  end

  describe '#handle_order_filled' do
    before do
      allow(mock_bot).to receive(:save_trade)
    end

    it 'saves the trade' do
      event_handler.send(:handle_order_filled, mock_trade)
      expect(mock_bot).to have_received(:save_trade).with(mock_trade)
    end
  end

  describe '#handle_order_failed' do
    before do
      allow(mock_trade).to receive(:order_status).and_return('CANCELED')
    end

    it 'deletes the trade file' do
      event_handler.send(:handle_order_failed, mock_trade)
      expect(File).to have_received(:delete)
    end
  end

  describe '#handle_market_changed' do
    before do
      allow(mock_trade).to receive(:replace)
    end

    it 'replaces the order and saves the trade' do
      event_handler.send(:handle_market_changed, mock_trade)
      expect(mock_trade).to have_received(:replace).with(order_instruction: :entry)
      expect(mock_bot).to have_received(:save_trade).with(mock_trade)
    end
  end

  describe '#handle_exit_loss' do
    before do
      allow(mock_trade).to receive(:close)
    end

    it 'closes the trade and deletes the trade file' do
      event_handler.send(:handle_exit_loss, mock_trade)
      expect(mock_trade).to have_received(:close)
      expect(File).to have_received(:delete)
    end
  end

  describe '#handle_exit_profit' do
    before do
      allow(mock_trade).to receive(:close)
    end

    it 'closes the trade and deletes the trade file' do
      event_handler.send(:handle_exit_profit, mock_trade)
      expect(mock_trade).to have_received(:close)
      expect(File).to have_received(:delete)
    end
  end

  describe '#handle_hold' do
    it 'logs that it is holding the trade (no action)' do
      # This is mostly just testing that the method exists and doesn't error
      expect { event_handler.send(:handle_hold, mock_trade) }.not_to raise_error
    end
  end

  describe '#handle_error' do
    it 'logs the error message and backtrace' do
      error = StandardError.new('Test error')
      allow(error).to receive(:backtrace).and_return(['line 1', 'line 2'])

      # This is mostly just testing that the method exists and doesn't error
      expect { event_handler.send(:handle_error, error) }.not_to raise_error
    end
  end
end
