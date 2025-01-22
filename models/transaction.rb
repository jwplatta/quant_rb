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
        position_id: data.fetch(:positionId),
        order_id: data.fetch(:orderId),
        net_amount: data.fetch(:netAmount),
        transfer_items: transfer_items
      )
    end
  end

  def initialize(activity_id:, time:, account_number:, type:, status:, sub_account:, trade_date:, position_id:, order_id:, net_amount:, transfer_items: [])
    @actibity_id = activity_id
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
