#!/usr/bin/env ruby

require_relative '../../config/environment'
require 'timeout'

class SourceColumnBackfill
  def initialize(start_id)
    @start_id = start_id
    @batch_size = 10
    @sleep_time = 0.25
  end

  def run
    current_id = @start_id
    batch_count = 0

    puts "Starting backfill from ID #{@start_id} with batch size #{@batch_size}"

    loop do
      end_id = current_id + @batch_size - 1

      begin
        Timeout::timeout(10) do
          ActiveRecord::Base.connection.execute(<<-SQL)
            BEGIN;
            SET LOCAL statement_timeout = '8s';
            UPDATE option_chain_history
            SET source = 'polygon'
            WHERE id >= #{current_id}
            AND id <= #{end_id}
            AND source IS NULL;
            COMMIT;
          SQL
        end

        batch_count += 1
        print "."
        puts " #{batch_count * @batch_size}" if batch_count % 200 == 0

      rescue => e
        puts "\nBatch #{current_id}-#{end_id} failed: #{e.message}"
      end

      current_id = end_id + 1
      sleep(@sleep_time)
    end
  end
end

start_id = ARGV[0]&.to_i

unless start_id && start_id > 0
  puts "Usage: ruby backfill_source_column.rb <start_id>"
  puts "Example: ruby backfill_source_column.rb 4047298"
  exit(1)
end

backfill = SourceColumnBackfill.new(start_id)

begin
  backfill.run
rescue Interrupt
  puts "\nStopped by user"
end