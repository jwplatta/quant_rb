class TradeEvent
  attr_reader :type, :payload

  def initialize(type, payload = {})
    @type = type
    @payload = payload
  end
end
