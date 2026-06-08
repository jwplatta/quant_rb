# frozen_string_literal: true

require "tzinfo"

module QuantRb
  module OptionExpiration
    DEFAULT_TIMEZONE = "America/New_York"
    DEFAULT_HOUR = 16
    DEFAULT_MINUTE = 0

    module_function

    def expiration_time_utc(expiration_date, timezone_name: DEFAULT_TIMEZONE, hour: DEFAULT_HOUR, minute: DEFAULT_MINUTE)
      timezone = TZInfo::Timezone.get(timezone_name)
      timezone.local_time(expiration_date.year, expiration_date.month, expiration_date.day, hour, minute, 0).utc
    end

    def expired?(expiration_date, target_time_utc, timezone_name: DEFAULT_TIMEZONE, hour: DEFAULT_HOUR, minute: DEFAULT_MINUTE)
      target_time_utc.getutc >= expiration_time_utc(expiration_date, timezone_name:, hour:, minute:)
    end

    def active?(expiration_date, target_time_utc, timezone_name: DEFAULT_TIMEZONE, hour: DEFAULT_HOUR, minute: DEFAULT_MINUTE)
      !expired?(expiration_date, target_time_utc, timezone_name:, hour:, minute:)
    end
  end
end
