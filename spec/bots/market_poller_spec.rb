# frozen_string_literal: true

require 'spec_helper'
require_relative '../../bots/market_poller'
require_relative '../../bots/trade_event'
require_relative '../../services/trades/null_trade'

RSpec.describe MarketPoller do
  let(:mock_queue) { instance_double(Queue) }
  let(:mock_bot) { double('Bot') }
  let(:mock_trade) { double('Trade') }
  let(:poller) { described_class.new(mock_bot, mock_queue, 0.01) }

  before do
    allow(mock_queue).to receive(:push)
  end

  describe '#initialize' do
    it 'sets up instance variables' do
      expect(poller.bot).to eq(mock_bot)
      expect(poller.queue).to eq(mock_queue)
      expect(poller.interval).to eq(0.01)
    end
  end

  describe '#start and #stop' do
    it 'starts and stops the polling thread' do
      # Mock poll to prevent the real method from being called
      allow(poller).to receive(:poll)

      # Test that the thread starts
      poller.start
      expect(poller.thread).to be_a(Thread)
      sleep(0.05) # Give thread time to start
      expect(poller.thread).to be_alive

      # Test that the thread stops
      poller.stop
      sleep(0.05) # Give the thread time to stop
      expect(poller.thread).not_to be_alive
    end
  end

  describe '#poll' do
    context 'when trade is nil' do
      it 'pushes find_new_trade event to the queue' do
        allow(mock_bot).to receive(:read_trade).and_return(nil)

        poller.send(:poll)

        expect(mock_queue).to have_received(:push) do |event|
          expect(event.type).to eq(:find_new_trade)
          expect(event.payload).to eq({})
        end
      end
    end

    context 'when trade is filled' do
      it 'determines action and pushes event to the queue' do
        allow(mock_bot).to receive(:read_trade).and_return(mock_trade)
        allow(mock_trade).to receive(:filled?).and_return(true)
        allow(mock_bot).to receive(:determine_action).with(mock_trade).and_return(:exit_profit)

        poller.send(:poll)

        expect(mock_queue).to have_received(:push) do |event|
          expect(event.type).to eq(:exit_profit)
          expect(event.payload[:trade]).to eq(mock_trade)
        end
      end
    end

    context 'when trade is not filled' do
      before do
        allow(mock_bot).to receive(:read_trade).and_return(mock_trade)
        allow(mock_trade).to receive(:filled?).and_return(false)
        allow(mock_trade).to receive(:check_order_status)
      end

      it 'checks order status' do
        allow(mock_trade).to receive(:failed?).and_return(false)
        allow(mock_trade).to receive(:working?).and_return(false)

        poller.send(:poll)

        expect(mock_trade).to have_received(:check_order_status)
      end

      context 'and becomes filled after status check' do
        it 'pushes order_filled event to the queue' do
          allow(mock_trade).to receive(:filled?).and_return(false, true)
          allow(mock_trade).to receive(:failed?).and_return(false)

          poller.send(:poll)

          expect(mock_queue).to have_received(:push) do |event|
            expect(event.type).to eq(:order_filled)
            expect(event.payload[:trade]).to eq(mock_trade)
          end
        end
      end

      context 'and failed status after check' do
        it 'pushes order_failed event to the queue' do
          allow(mock_trade).to receive(:filled?).and_return(false)
          allow(mock_trade).to receive(:failed?).and_return(true)

          poller.send(:poll)

          expect(mock_queue).to have_received(:push) do |event|
            expect(event.type).to eq(:order_failed)
            expect(event.payload[:trade]).to eq(mock_trade)
          end
        end
      end

      context 'and still working but market conditions changed' do
        it 'pushes market_changed event to the queue' do
          allow(mock_trade).to receive(:filled?).and_return(false)
          allow(mock_trade).to receive(:failed?).and_return(false)
          allow(mock_trade).to receive(:working?).and_return(true)
          allow(mock_bot).to receive(:market_conditions_changed?).with(mock_trade).and_return(true)

          poller.send(:poll)

          expect(mock_queue).to have_received(:push) do |event|
            expect(event.type).to eq(:market_changed)
            expect(event.payload[:trade]).to eq(mock_trade)
          end
        end
      end
    end

    context 'when an error occurs' do
      it 'pushes error event to the queue' do
        error = StandardError.new('Test error')
        allow(mock_bot).to receive(:read_trade).and_raise(error)

        poller.send(:poll)

        expect(mock_queue).to have_received(:push) do |event|
          expect(event.type).to eq(:error)
          expect(event.payload[:error]).to eq(error)
        end
      end
    end
  end
end
