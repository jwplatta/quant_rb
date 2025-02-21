require "schwab_rb"
require "dotenv"
require_relative "data_objects/quote"
require_relative "data_objects/option_chain"

Dotenv.load

module Schwab
  def self.client
    token_path = ENV["TOKEN_PATH"]
    SchwabRb::Auth.init_client_easy(
      ENV["SCHWAB_API_KEY"],
      ENV["SCHWAB_APP_SECRET"],
      ENV["APP_CALLBACK_URL"],
      token_path
    )
  end

  def self.quote(symbol)
    client.get_quote(symbol).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        DataObjects::QuoteFactory.build(data)
      end
    end
  end

  def self.option_chain(symbol, strike_range: "OTM", from_date: Date.today, to_date: Date.today + 30)
    client.get_option_chain(
      symbol,
      strike_range: strike_range,
      from_date: from_date,
      to_date: to_date
    ).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        DataObjects::OptionChain.build(data)
      end
    end
  end
end
