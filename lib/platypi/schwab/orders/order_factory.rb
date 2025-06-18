# frozen_string_literal: true

require 'schwab_rb'
require_relative 'iron_condor_order'
require_relative 'vertical_order'

module Platypi
  module Schwab
    module Orders
      class OrderFactory
        class << self
          def build(strategy, **options)
            case strategy.class.name
            when 'Platypi::IronCondor'
              IronCondorOrder.build(strategy, **options)
            when 'Platypi::CallSpread', 'Platypi::PutSpread'
              VerticalOrder.build(strategy, **options)
            else
              raise 'Unsupported trade strategy'
            end
          end
        end
      end
    end
  end
end
