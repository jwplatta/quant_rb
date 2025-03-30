require "dotenv"

Dotenv.load

class BotBase
  def initialize(symbol: nil)
    @symbol = symbol
  end

  attr_reader :symbol
end
