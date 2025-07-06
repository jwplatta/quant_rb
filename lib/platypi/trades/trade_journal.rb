# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'dotenv'
require 'pry'

module Platypi
  module Trades
    class TradeJournal
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

        def read_or_init(trade_id)
          new(trade_id)
        end

        def trade_open?(trade_id)
          journal = new(trade_id)
          journal.trade_exited_event.nil? && !journal.trade_entered_event.nil?
        rescue Errno::ENOENT
          false
        end
      end

      def initialize(trade_id)
        @trade_id = trade_id
        self.class.ensure_directory_exists
        FileUtils.touch(file_path) unless File.exist?(file_path)
      end

      attr_reader :trade_id

      def log(trade)
        reset
        File.open(file_path, 'a') do |file|
          file.puts(trade.to_json)
        end
      end

      def reset
        @trade_history = nil
        @last_event = nil
        @trade_adjustment_events = nil
      end

      def last_event
        @last_event ||= trade_history.min_by { |trade_event| trade_event.timestamp }
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
        @trade_history ||= File.readlines(file_path).map do |line|
          line = line.strip
          next if line.empty?

          begin
            Platypi::Trades::Trade.from_json(line)
          rescue JSON::ParserError => e
            puts "Error parsing trade history line: #{e.message}"
            nil
          end
        end.compact
      end
    end
  end
end
