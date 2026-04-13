# frozen_string_literal: true

require_relative "lib/quant_rb/version"

Gem::Specification.new do |spec|
  spec.name    = "quant_rb"
  spec.version = QuantRb::VERSION
  spec.authors = ["Joseph Platta"]
  spec.email   = ["jwplatta@gmail.com"]

  spec.summary     = "QuantConnect-inspired algorithmic trading and backtesting engine for Ruby"
  spec.description = "A general-purpose event-driven backtesting engine for algorithmic strategies " \
                     "across all asset classes (stocks, ETFs, indexes, options, futures). " \
                     "Strategy code runs unchanged across backtesting, paper trading, and live trading " \
                     "by swapping data source and broker adapters."
  spec.homepage    = "https://github.com/jwplatta/quant_rb"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile bots/])
    end
  end

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "dotenv", ">= 2.0"

  # Development dependencies
  spec.add_development_dependency "factory_bot", "~> 6.4"
  spec.add_development_dependency "pry",         ">= 0.14"
  spec.add_development_dependency "rspec",       "~> 3.12"
  spec.add_development_dependency "rubocop",     ">= 1.50"
  spec.add_development_dependency "timecop",     ">= 0.9"
end
