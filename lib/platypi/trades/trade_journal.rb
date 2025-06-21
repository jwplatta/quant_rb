# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'dotenv'
require 'pry'

module Platypi
  class TradeJournal
    class << self
      def base_path
        @base_path ||= ENV.fetch('TRADE_JOURNAL_PATH', File.join(Dir.home, '.platypi', 'trade_journal'))
      end

      def open_trades_path
        @open_trades_path ||= File.join(base_path, 'open')
      end

      def closed_trades_path
        @closed_trades_path ||= File.join(base_path, 'closed')
      end

      def ensure_directories_exist
        FileUtils.mkdir_p(open_trades_path)
        FileUtils.mkdir_p(closed_trades_path)
      end

      def mutex
        @mutex ||= Mutex.new
      end

      # Load all currently open trades
      def load_open_trades
        ensure_directories_exist
        trades = []

        Dir.glob(File.join(open_trades_path, '*.jsonl')).each do |file_path|
          trade = load_latest_trade_from_file(file_path)
          trades << trade if trade && trade_is_open?(trade)
        end

        trades
      end

      # Load a specific trade by ID (checks both open and closed)
      def load_trade(trade_id)
        file_path = find_trade_file(trade_id)
        return nil unless file_path

        load_latest_trade_from_file(file_path)
      end

      # Check if a specific trade exists and is open
      def trade_open?(trade_id)
        file_path = File.join(open_trades_path, "#{trade_id}.jsonl")
        return false unless File.exist?(file_path)

        trade = load_latest_trade_from_file(file_path)
        trade && trade_is_open?(trade)
      end

      # Get count of open trades
      def open_trade_count
        Dir.glob(File.join(open_trades_path, '*.jsonl')).count
      end

      # Load all closed trades (just latest state)
      def load_closed_trades
        ensure_directories_exist
        trades = []

        Dir.glob(File.join(closed_trades_path, '*.jsonl')).each do |file_path|
          trade = load_latest_trade_from_file(file_path)
          trades << trade if trade
        end

        trades
      end

      private

      def find_trade_file(trade_id)
        filename = "#{trade_id}.jsonl"
        open_file = File.join(open_trades_path, filename)
        closed_file = File.join(closed_trades_path, filename)

        return open_file if File.exist?(open_file)
        return closed_file if File.exist?(closed_file)
        nil
      end

      def load_latest_trade_from_file(file_path)
        return nil unless File.exist?(file_path)

        # Read the last line of the file (most recent trade state)
        last_line = File.readlines(file_path).last&.strip
        return nil if last_line.nil? || last_line.empty?

        Platypi::Trades::Trade.from_json(last_line)
      rescue JSON::ParserError, StandardError => e
        puts "Error loading trade from #{file_path}: #{e.message}"
        nil
      end

      def trade_is_open?(trade)
        %w[OPEN PREVIEW_OPEN].include?(trade.status)
      end
    end

    def initialize(trade_id)
      @trade_id = trade_id
      self.class.ensure_directories_exist
    end

    attr_reader :trade_id

    def save_trade(trade)
      # Only synchronize file writing and moving operations
      self.class.mutex.synchronize do
        write_trade_to_file(trade)
        move_to_closed_if_needed(trade)
      end
    end

    def load_trade
      self.class.load_trade(trade_id)
    end

    # Get the current file path for this trade
    def current_file_path
      filename = "#{trade_id}.jsonl"
      open_file = File.join(self.class.open_trades_path, filename)
      closed_file = File.join(self.class.closed_trades_path, filename)

      return open_file if File.exist?(open_file)
      return closed_file if File.exist?(closed_file)

      # Default to open folder for new trades
      open_file
    end

    # Get all states of this trade (useful for history/debugging)
    def trade_history
      file_path = current_file_path
      return [] unless File.exist?(file_path)

      File.readlines(file_path).map do |line|
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

    # Delete this trade's file (useful for cleanup/testing)
    def delete_trade
      # Synchronize file deletion
      self.class.mutex.synchronize do
        file_path = current_file_path
        File.delete(file_path) if File.exist?(file_path)
      end
    end

    # Find the trade state with OPEN status from the history
    def open_state
      trade_history.find { |state| %w[OPEN PREVIEW_OPEN].include?(state.status) }
    end

    private

    def write_trade_to_file(trade)
      file_path = current_file_path

      # Ensure we're writing to the open folder for active trades
      if trade_is_active?(trade)
        file_path = File.join(self.class.open_trades_path, "#{trade_id}.jsonl")
      end

      File.open(file_path, 'a') do |file|
        file.puts(trade.to_json)
      end
    end

    def move_to_closed_if_needed(trade)
      return unless trade_is_closed?(trade)

      open_file = File.join(self.class.open_trades_path, "#{trade_id}.jsonl")
      closed_file = File.join(self.class.closed_trades_path, "#{trade_id}.jsonl")

      if File.exist?(open_file)
        FileUtils.mv(open_file, closed_file)
      end
    end

    def trade_is_active?(trade)
      %w[OPEN PREVIEW_OPEN].include?(trade.status)
    end

    def trade_is_closed?(trade)
      %w[EXIT PREVIEW_EXIT ERROR].include?(trade.status)
    end
  end
end
