require_relative "instrument"

class TransferItem
  class << self
    def build(data)
      TransferItem.new(
        instrument: Instrument.build(data.fetch(:instrument)),
        amount: data.fetch(:amount),
        cost: data.fetch(:cost),
        fee_type: data.fetch(:feeType, nil),
      )
    end
  end
  def initialize(instrument:, amount:, cost:, fee_type:)
    @instrument = instrument
    @amount = amount
    @cost = cost
    @fee_type = fee_type
  end

  attr_reader :instrument, :amount, :cost, :fee_type
end

class Transaction
  class << self
    def build(data)
      Transaction.new(
        activity_id: data.fetch(:activityId),
        time: data.fetch(:time),
        account_number: data.fetch(:accountNumber),
        type: data.fetch(:type),
        status: data.fetch(:status),
        sub_account: data.fetch(:subAccount),
        trade_date: data.fetch(:tradeDate),
        position_id: data.fetch(:positionId, nil),
        order_id: data.fetch(:orderId, nil),
        net_amount: data.fetch(:netAmount),
        transfer_items: data.fetch(:transferItems).map { |ti| TransferItem.build(ti) }
      )
    end
  end

  def initialize(activity_id:, time:, account_number:, type:, status:, sub_account:, trade_date:, position_id:, order_id:, net_amount:, transfer_items: [])
    @activity_id = activity_id
    @time = time
    @account_number = account_number
    @type = type
    @status = status
    @sub_account = sub_account
    @trade_date = trade_date
    @position_id = position_id
    @order_id = order_id
    @net_amount = net_amount
    @transfer_items = transfer_items
  end

  attr_reader :activity_id, :time, :account_number, :type, :status, :sub_account, :trade_date, :position_id, :order_id, :net_amount, :transfer_items
end
