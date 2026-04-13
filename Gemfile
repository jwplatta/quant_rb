# frozen_string_literal: true

source "https://rubygems.org"
ruby ">= 3.1.0"

gemspec path: ".", name: "quant_rb"

gem "dotenv"
gem "pry"
gem "rake"

group :development, :test do
  gem "factory_bot", "~> 6.5"
  gem "rspec",       "~> 3.12"
  gem "rubocop",     require: false
  gem "timecop"
end
