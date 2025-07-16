module OptionsTrader
  class Adjustment
    def initialize(old_strategy, new_strategy)
      @old_strategy = old_strategy
      @new_strategy = new_strategy
    end

    attr_reader :new_strategy, :old_strategy

    def credit_debit
    end

    def net_credit_debit
    end
  end
end
