# frozen_string_literal: true

module QuantRb
  module Engine
    # Builds date-matching rules used with Scheduler#on.
    #
    # Usage:
    #   date_rules.every_day(symbol)
    #   date_rules.on(2024, 3, 15)
    #
    # TODO (Phase 3): Implement full date rule logic including market calendar awareness.
    #
    class DateRules
      # Matches every weekday (Mon-Fri). symbol is ignored for now (market calendar support future).
      def every_day(_symbol = nil)
        EveryDayRule.new
      end

      # Matches a specific calendar date.
      def on(year, month, day)
        SpecificDateRule.new(Date.new(year, month, day))
      end

      class EveryDayRule
        def matches?(time)
          wday = time.respond_to?(:wday) ? time.wday : time.to_date.wday
          wday >= 1 && wday <= 5  # Mon-Fri
        end
      end

      class SpecificDateRule
        def initialize(date)
          @date = date
        end

        def matches?(time)
          time.to_date == @date
        end
      end
    end
  end
end
