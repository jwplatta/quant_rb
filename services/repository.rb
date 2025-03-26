require_relative "../config/environment"

# Repository pattern to handle data access
class Repository
  # Trade methods
  def self.save_trade(trade_data)
    DB::Trade.create!(trade_data)
  end
  
  def self.find_trade(id)
    DB::Trade.find(id)
  end
  
  def self.find_trades_by_underlying(symbol)
    DB::Trade.where(underlying: symbol)
  end
  
  def self.find_open_trades
    DB::Trade.where(close_date: nil)
  end
  
  # Trade Leg methods
  def self.save_trade_leg(trade_leg_data)
    DB::TradeLeg.create!(trade_leg_data)
  end
  
  def self.find_legs_for_trade(trade_id)
    DB::TradeLeg.where(trade_id: trade_id)
  end
  
  # Order methods
  def self.save_order(order_data)
    DB::Order.create!(order_data)
  end
  
  def self.find_order(order_id)
    DB::Order.find_by(order_id: order_id)
  end
  
  def self.find_orders_for_trade(trade_id)
    DB::Order.where(trade_id: trade_id)
  end
  
  # Transaction methods
  def self.save_transaction(transaction_data)
    DB::Transaction.create!(transaction_data)
  end
  
  def self.find_transactions_for_order(order_id)
    DB::Transaction.where(order_id: order_id)
  end
  
  # Example of a more complex query
  def self.find_complete_trade(trade_id)
    trade = DB::Trade.find(trade_id)
    legs = DB::TradeLeg.where(trade_id: trade_id)
    orders = DB::Order.where(trade_id: trade_id)
    transactions = DB::Transaction.joins(:order).where(orders: { trade_id: trade_id })
    
    {
      trade: trade,
      legs: legs,
      orders: orders,
      transactions: transactions
    }
  end
end