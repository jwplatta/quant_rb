# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'dotenv'
require 'pry'

module Platypi
  module Trades
    class TradeJournal
      include Platypi::Loggable

      class << self
        def base_path
          ENV.fetch(
            'TRADE_JOURNAL_PATH',
            File.join(Dir.home, '.platypi', 'trade_journal')
          )
        end

        def ensure_directory_exists
          FileUtils.mkdir_p(base_path) unless Dir.exist?(base_path)
        end

        def last_event(trade_id)
          file_path = File.join(base_path, "trade_#{trade_id}.jsonl")
          all_events = File.readlines(file_path).map do |line|
            line = line.strip
            next if line.empty?

            begin
              Platypi::Trades::Trade.from_json(line)
            rescue JSON::ParserError => e
              logger.error("Error parsing trade history line: #{e.message}")
              nil
            end
          end.compact

          if all_events.empty?
            logger.warn("No trade events found for #{trade_id}.")
            nil
          else
            all_events.min_by { |event| event.timestamp }
          end
        rescue Errno::ENOENT
          logger.error("Trade journal for #{trade_id} does not exist.")
          nil
        end
      end

      def initialize(trade_id:)
        raise ArgumentError, 'trade_id must be provided' if trade_id.nil? || trade_id.empty?

        @trade_id = trade_id
        @last_event = nil
        @trade_history = []
        FileUtils.touch(file_path) unless File.exist?(file_path)
      end

      attr_reader :trade_id

      def trade_open?
        trade_exited_event.nil? && !journal.trade_entered_event.nil?
      end

      def trade_exited?
        !trade_exited_event.nil?
      end

      def save(trade)
        @last_event = trade.clone

        if @last_event.current_state == 'TRADE_OPEN'
          progress_perc = (@last_event.progress.progress_perc).round(2)
          profit_loss = (@last_event.progress.current_pnl).round(2)
          log_trade_state(@last_event.trade_id, @last_event.current_state, "#{progress_perc}% | $#{profit_loss}")
        elsif @last_event.current_state == 'TRADE_FOUND'
          log_trade_state(@last_event.trade_id, @last_event.current_state, @last_event.strategy.to_s)
        else
          log_trade_state(@last_event.trade_id, @last_event.current_state)
        end

        File.open(file_path, 'a') do |file|
          file.puts(@last_event.to_json)
        end
      end

      def trade_entered_event
        @trade_entered_event ||= trade_history.find { |event| event.current_state == 'TRADE_ENTERED' }
      end

      def trade_exited_event
        @trade_exited_event ||= trade_history.find { |event| event.current_state == 'TRADE_EXITED' }
      end

      def trade_adjustment_events
        @trade_adjustment_events ||= trade_history.select { |event| ['ADJUST_EXITED', 'ADJUST_ENTERED'].include?(event.current_state) }
      end

      def file_path
        @file_path ||= File.join(
          self.class.base_path,
          "trade_#{trade_id}.jsonl"
        )
      end

      def trade_history
        File.readlines(file_path).map do |line|
          line = line.strip
          next if line.empty?

          begin
            Platypi::Trades::Trade.from_json(line)
          rescue JSON::ParserError => e
            logger.error("Error parsing trade history line: #{e.message}")
            nil
          end
        end.compact
      end
    end
  end
end
