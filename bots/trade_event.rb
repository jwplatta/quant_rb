# frozen_string_literal: true

class TradeEvent
  attr_reader :type, :delay, :payload, :timestamp, :action

  def initialize(type: 'action', delay: 0, action: nil, payload: {})
    @type = type
    @action = action
    @delay = delay
    @payload = payload
    @timestamp = Time.now.utc
  end
end
