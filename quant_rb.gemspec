# frozen_string_literal: true

require_relative "lib/quant_rb/version"

Gem::Specification.new do |spec|
  spec.name    = "quant_rb"
  spec.version = QuantRb::VERSION
  spec.authors = ["Joseph Platta"]
  spec.email   = ["jwplatta@gmail.com"]

  spec.summary     = "Event-driven backtesting engine for algorithmic trading strategies in Ruby"
  spec.description = "quant_rb is a QuantConnect-inspired backtesting engine for Ruby. " \
                     "Version #{QuantRb::VERSION} focuses on local-data backtesting for equities, indexes, " \
                     "and options. Paper trading and live trading adapters are planned future work and are " \
                     "not included in this first release."
  spec.homepage    = "https://github.com/jwplatta/options_trader"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

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
  spec.add_development_dependency "pry",         ">= 0.14"
  spec.add_development_dependency "rake",        ">= 13.0"
  spec.add_development_dependency "rspec",       "~> 3.12"
  spec.add_development_dependency "rubocop",     ">= 1.50"
end
