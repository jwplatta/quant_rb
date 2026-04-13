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
      # Matches a specific hour:minute (wall clock, no timezone handling yet).
      def at(hour, minute)
        AtRule.new(hour, minute)
      end

      # Matches every N minutes.
      def every(minutes: 1)
        EveryNMinutesRule.new(minutes)
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
          @n = n
        end

        def matches?(time)
          time.min % @n == 0
        end
      end
    end
  end
end
