module OptionsTrader
  module DataProviders
    module Schwab
      class Orders
        def client
          OptionsTrader::DataProviders::Schwab::Client.instance
        end
      end
    end
  end
end
