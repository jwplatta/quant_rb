# frozen_string_literal: true

require "ruby-progressbar"

module QuantRb
  module Reporting
    # Thin wrapper around terminal progress output so engine code does not
    # depend directly on the progress bar library or TTY heuristics.
    class ProgressReporter
      attr_reader :enabled

      def initialize(total:, title:, enabled: :auto, output: $stdout)
        @enabled = progress_enabled?(enabled, output) && total.to_i.positive?
        @progress_bar = build_progress_bar(total, title) if @enabled
      end

      def increment
        @progress_bar&.increment
      end

      def finish
        @progress_bar&.finish
      end

      private

      def progress_enabled?(enabled, output)
        case enabled
        when :auto then output.tty?
        when true then true
        when false, nil then false
        else
          raise ArgumentError, "progress must be :auto, true, or false"
        end
      end

      def build_progress_bar(total, title)
        ProgressBar.create(
          total: total,
          title: title,
          format: "%t |%B| %c/%C %p%% %e"
        )
      end
    end
  end
end
