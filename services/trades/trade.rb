require 'schwab_rb'

class Trade
  def send
  end

  def replace
  end

  def cancel
  end

  def build_order
    to_order
  end

  def preview
  end

  def round_to_nearest_five_cent(value)
    (value / 0.05).floor * 0.05
  end
end
