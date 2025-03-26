-- This file is here for reference, but we're using ActiveRecord migrations
-- SQLite database setup script

-- Trades table
CREATE TABLE IF NOT EXISTS trades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  underlying VARCHAR(20) NOT NULL,
  strategy_type VARCHAR(50) NOT NULL,
  open_date DATE NOT NULL,
  close_date DATE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Trade legs table
CREATE TABLE IF NOT EXISTS trade_legs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  put_call VARCHAR(10) NOT NULL,
  symbol VARCHAR(50) NOT NULL,
  mark DECIMAL(10,2) NOT NULL,
  ask DECIMAL(10,2) NOT NULL,
  bid DECIMAL(10,2) NOT NULL,
  delta DECIMAL(10,2) NOT NULL,
  strike DECIMAL(10,2) DEFAULT 0.0,
  expiration_date DATE NOT NULL,
  instruction VARCHAR(20) NOT NULL,
  quantity INTEGER DEFAULT 1,
  trade_id INTEGER,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (trade_id) REFERENCES trades(id)
);

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id VARCHAR(50) NOT NULL,
  order_type VARCHAR(50) NOT NULL,
  underlying VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  strategy_type VARCHAR(50) NOT NULL,
  adjustment BOOLEAN DEFAULT 0,
  net_amount DECIMAL(10,2) DEFAULT 0.0,
  trade_id INTEGER,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (trade_id) REFERENCES trades(id)
);

-- Transactions table
CREATE TABLE IF NOT EXISTS transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol VARCHAR(50) NOT NULL,
  description TEXT NOT NULL,
  put_call VARCHAR(10) NOT NULL,
  trade_date DATETIME NOT NULL,
  instrument_id INTEGER NOT NULL,
  quantity INTEGER DEFAULT 0,
  fees DECIMAL(10,2) DEFAULT 0.0,
  commission DECIMAL(10,2) DEFAULT 0.0,
  cost DECIMAL(10,2) DEFAULT 0.0,
  net_amount DECIMAL(10,2) DEFAULT 0.0,
  position_effect VARCHAR(20) NOT NULL,
  order_id INTEGER,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES orders(id)
);