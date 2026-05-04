# frozen_string_literal: true

require "tzinfo"

module QuantRb
  module MarketTime
    module_function

    def timezone(name = nil)
      TZInfo::Timezone.get((name || QuantRb.config.market_timezone).to_s)
    end

    def local_time(time, timezone_name = nil)
      timezone(timezone_name).utc_to_local(time.getutc)
    end

    def market_date(time, timezone_name = nil)
      local_time(time, timezone_name).to_date
    end

    def days_to_expiration(expiration_date, time, timezone_name = nil)
      expiration_date - market_date(time, timezone_name)
    end
  end
end
