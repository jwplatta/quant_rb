require 'nokogiri'
require 'open-uri'

SYMBOL = 'AAPL'
url = "https://finance.yahoo.com/quote/#{SYMBOL}"
page = Nokogiri::HTML(URI.open(url))
price = page.at_css('fin-streamer[data-field="regularMarketPrice"]').text

puts "Current price for #{SYMBOL}: $#{price}"