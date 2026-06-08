# frozen_string_literal: true

require "time"

module QuantRb
  module Data
    module OptionChainSampleTime
      module_function

      def parse_filename_timestamp(sample_date, sample_time)
        Time.strptime("#{sample_date} #{sample_time.tr('-', ':')} UTC", "%Y-%m-%d %H:%M:%S %Z").utc
      end
    end
  end
end
