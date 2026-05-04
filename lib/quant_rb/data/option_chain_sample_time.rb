# frozen_string_literal: true

require "time"

module QuantRb
  module Data
    module OptionChainSampleTime
      CST_UTC_OFFSET = "-06:00"

      module_function

      def parse_filename_timestamp(sample_date, sample_time)
        Time.strptime(
          "#{sample_date} #{sample_time.tr('-', ':')} #{CST_UTC_OFFSET}",
          "%Y-%m-%d %H:%M:%S %z"
        ).utc
      end
    end
  end
end
