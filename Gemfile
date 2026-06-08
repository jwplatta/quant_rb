# frozen_string_literal: true

source "https://rubygems.org"
ruby ">= 3.1.0"

gemspec path: ".", name: "quant_rb"

gem "dotenv"
gem "pry", ">= 0.14"
gem "rake", ">= 13.0"
gem "ruby-progressbar", ">= 1.13"
gem "tickrake", github: "jwplatta/tickrake", branch: "main"

group :development, :test do
  gem "rspec",       "~> 3.12"
  gem "rubocop",     ">= 1.50", require: false
end
