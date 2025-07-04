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
          @base_path ||= ENV.fetch(
            'TRADE_JOURNAL_PATH',
            File.join(Dir.home, '.platypi', 'trade_journal')
          )
        end

        def ensure_directory_exists
          FileUtils.mkdir_p(base_path) unless Dir.exist?(base_path)
        end
      end

      def initialize(trade_id)
        @trade_id = trade_id
        self.class.ensure_directory_exists
        FileUtils.touch(file_path) unless File.exist?(file_path)
      end

      attr_reader :trade_id

      def log(trade)
        File.open(file_path, 'a') do |file|
          file.puts(trade.state_to_json)
        end
      end

      def last_state
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
