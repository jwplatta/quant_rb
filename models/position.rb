class Position
  attr_reader :short_quantity, :average_price, :current_day_profit_loss, :current_day_profit_loss_percentage,
              :long_quantity, :settled_long_quantity, :settled_short_quantity, :instrument, :market_value,
              :maintenance_requirement, :average_long_price, :average_short_price, :tax_lot_average_long_price,
              :tax_lot_average_short_price, :long_open_profit_loss, :short_open_profit_loss,
              :previous_session_long_quantity, :previous_session_short_quantity, :current_day_cost

  class << self
    def build(data)
      new(
        short_quantity: data[:shortQuantity],
        average_price: data[:averagePrice],
        current_day_profit_loss: data[:currentDayProfitLoss],
        current_day_profit_loss_percentage: data[:currentDayProfitLossPercentage],
        long_quantity: data[:longQuantity],
        settled_long_quantity: data[:settledLongQuantity],
        settled_short_quantity: data[:settledShortQuantity],
        instrument: Instrument.build(data[:instrument]),
        market_value: data[:marketValue],
        maintenance_requirement: data[:maintenanceRequirement],
        average_long_price: data[:averageLongPrice],
        average_short_price: data[:averageShortPrice],
        tax_lot_average_long_price: data[:taxLotAverageLongPrice],
        tax_lot_average_short_price: data[:taxLotAverageShortPrice],
        long_open_profit_loss: data[:longOpenProfitLoss],
        short_open_profit_loss: data[:shortOpenProfitLoss],
        previous_session_long_quantity: data[:previousSessionLongQuantity],
        previous_session_short_quantity: data[:previousSessionShortQuantity],
        current_day_cost: data[:currentDayCost]
      )
    end
  end

  def initialize(short_quantity:, average_price:, current_day_profit_loss:, current_day_profit_loss_percentage:,
                 long_quantity:, settled_long_quantity:, settled_short_quantity:, instrument:, market_value:,
                 maintenance_requirement:, average_long_price: nil, average_short_price: nil,
                 tax_lot_average_long_price: nil, tax_lot_average_short_price: nil, long_open_profit_loss: nil,
                 short_open_profit_loss: nil, previous_session_long_quantity:, previous_session_short_quantity:,
                 current_day_cost:)
    @short_quantity = short_quantity
    @average_price = average_price
    @current_day_profit_loss = current_day_profit_loss
    @current_day_profit_loss_percentage = current_day_profit_loss_percentage
    @long_quantity = long_quantity
    @settled_long_quantity = settled_long_quantity
    @settled_short_quantity = settled_short_quantity
    @instrument = instrument
    @market_value = market_value
    @maintenance_requirement = maintenance_requirement
    @average_long_price = average_long_price
    @average_short_price = average_short_price
    @tax_lot_average_long_price = tax_lot_average_long_price
    @tax_lot_average_short_price = tax_lot_average_short_price
    @long_open_profit_loss = long_open_profit_loss
    @short_open_profit_loss = short_open_profit_loss
    @previous_session_long_quantity = previous_session_long_quantity
    @previous_session_short_quantity = previous_session_short_quantity
    @current_day_cost = current_day_cost
  end
end
