class Instrument
  attr_reader :asset_type, :cusip, :symbol, :description, :net_change, :type, :put_call, :underlying_symbol

  def self.build(data)
    new(
      asset_type: data[:assetType],
      cusip: data[:cusip],
      symbol: data[:symbol],
      description: data[:description],
      net_change: data[:netChange],
      type: data[:type],
      put_call: data[:putCall],
      underlying_symbol: data[:underlyingSymbol]
    )
  end

  def initialize(asset_type:, cusip:, symbol:, description:, net_change:, type:, put_call:, underlying_symbol:)
    @asset_type = asset_type
    @cusip = cusip
    @symbol = symbol
    @description = description
    @net_change = net_change
    @type = type
    @put_call = put_call
    @underlying_symbol = underlying_symbol
  end
end
