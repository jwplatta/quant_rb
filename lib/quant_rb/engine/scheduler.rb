# frozen_string_literal: true

module QuantRb
  module Engine
    # Manages time-based callbacks. Used via strategy.schedule.on(date_rule, time_rule, callback).
    #
    # TODO (Phase 3): Implement full scheduling logic.
    #
    class Scheduler
      ScheduledEvent = Struct.new(:date_rule, :time_rule, :callback, :last_fired_at, keyword_init: true)

      def initialize
        @events = []
      end

      # Register a callback to fire when both date_rule and time_rule match.
      def on(date_rule, time_rule, callback)
        @events << ScheduledEvent.new(date_rule: date_rule, time_rule: time_rule, callback: callback)
        self
      end

      # Called by BacktestEngine on each time step. Fires matching callbacks.
      def fire(current_time)
        @events.each do |event|
          next unless event.date_rule.matches?(current_time) && event.time_rule.matches?(current_time)
          next if event.last_fired_at == current_time

          event.callback.call
          event.last_fired_at = current_time
        end
      end

      def events
        @events.dup.freeze
      end
    end
  end
end
