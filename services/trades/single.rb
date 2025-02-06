class Single < Trade
  def initialize(position:, exit_threshold: 0.75, approx_fees: 0.0)
    @strategy = "SINGLE"
    @position = position
    @exit_threshold = exit_threshold
  end
end
