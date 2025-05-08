require_relative "../config/environment"

class Repository
  def self.save_trade(trade_data)
    Persistance::Trade.create!(trade_data)
  end

  def self.find_trade(id)
    Persistance::Trade.find(id)
  end

  def self.find_trades_by_underlying(symbol)
    Persistance::Trade.where(underlying: symbol)
  end

  def self.find_open_trades
    Persistance::Trade.where(close_date: nil)
  end

  def self.save_trade_leg(trade_leg_data)
    Persistance::TradeLeg.create!(trade_leg_data)
  end

  def self.find_legs_for_trade(trade_id)
    Persistance::TradeLeg.where(trade_id: trade_id)
  end

  def self.save_order(order_data)
    Persistance::Order.create!(order_data)
  end

  def self.find_order(order_id)
    Persistance::Order.find_by(order_id: order_id)
  end

  def self.find_orders_for_trade(trade_id)
    Persistance::Order.where(trade_id: trade_id)
  end

  def self.save_transaction(transaction_data)
    Persistance::Transaction.create!(transaction_data)
  end

  def self.find_transactions_for_order(order_id)
    Persistance::Transaction.where(order_id: order_id)
  end

  def self.find_complete_trade(trade_id)
    trade = Persistance::Trade.find(trade_id)
    legs = Persistance::TradeLeg.where(trade_id: trade_id)
    orders = Persistance::Order.where(trade_id: trade_id)
    transactions = Persistance::Transaction.joins(:order).where(orders: { trade_id: trade_id })

    {
      trade: trade,
      legs: legs,
      orders: orders,
      transactions: transactions
    }
  end
end