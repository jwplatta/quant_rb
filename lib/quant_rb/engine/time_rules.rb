# frozen_string_literal: true

module QuantRb
  module Engine
    # Builds time-matching rules used with Scheduler#on.
    #
    # Usage:
    #   time_rules.at(15, 0)          # exactly 3:00 PM
    #   time_rules.every(minutes: 5)  # every 5 minutes
    #
    # TODO (Phase 3): Add market_open / market_close offset rules.
    #
    class TimeRules
      DEFAULT_MARKET_OPEN = [9, 30].freeze
      DEFAULT_MARKET_CLOSE = [16, 0].freeze

      # Matches a specific hour:minute (wall clock, no timezone handling yet).
      def at(hour, minute)
        AtRule.new(hour, minute)
      end

      # Matches every N minutes.
      def every(minutes: 1)
        EveryNMinutesRule.new(minutes)
      end

      def market_open(offset_minutes: 0)
        hour, minute = shifted_time(DEFAULT_MARKET_OPEN, offset_minutes)
        AtRule.new(hour, minute)
      end

      def market_close(offset_minutes: 0)
        hour, minute = shifted_time(DEFAULT_MARKET_CLOSE, offset_minutes)
        AtRule.new(hour, minute)
      end

      private

      def shifted_time(base_time, offset_minutes)
        minutes_since_midnight = (base_time[0] * 60) + base_time[1] + offset_minutes
        normalized = minutes_since_midnight % (24 * 60)
        [normalized / 60, normalized % 60]
      end

      class AtRule
        def initialize(hour, minute)
          @hour   = hour
          @minute = minute
        end

        def matches?(time)
          time.hour == @hour && time.min == @minute
        end
      end

      class EveryNMinutesRule
        def initialize(n)
          raise ArgumentError, "minutes must be positive" unless n.to_i.positive?

          @n = n
        end

        def matches?(time)
          time.min % @n == 0
        end
      end
    end
  end
end
