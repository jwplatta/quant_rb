require "schwab_rb"
require "dotenv"

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
end
