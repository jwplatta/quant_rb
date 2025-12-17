# frozen_string_literal: true

require_relative "lib/options_trader/version"

Gem::Specification.new do |spec|
  spec.name = "options_trader"
  spec.version = OptionsTrader::VERSION
  spec.authors = ["Joseh Platta"]
  spec.email = ["jwplatta@gmail.com"]

  spec.summary = "Comprehensive options trading automation system"
  spec.description = "A Ruby gem for automated options trading with support for various strategies including Iron Condors, Call/Put Spreads, and individual options. Features bot automation, trade lifecycle management, market data integration, and comprehensive backtesting capabilities."
  spec.homepage = "https://github.com/jwplatta/options_trader"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jwplatta/options_trader"
  spec.metadata["changelog_uri"] = "https://github.com/jwplatta/options_trader/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "activerecord", "~> 7.0"
  spec.add_runtime_dependency "clockwork", ">= 3.0"
  spec.add_runtime_dependency "dotenv", ">= 2.0"
  spec.add_runtime_dependency "pg", "~> 1.6"
  spec.add_runtime_dependency "pqueue", ">= 2.0"
  spec.add_runtime_dependency "rake", ">= 13.0"
  spec.add_runtime_dependency "schwab_rb", "~> 0.3.8"
  spec.add_runtime_dependency "sidekiq", ">= 7.0"
  spec.add_runtime_dependency "sqlite3", "~> 2.1"

  # Development dependencies
  spec.add_development_dependency "factory_bot", "~> 6.4"
  spec.add_development_dependency "pry", ">= 0.14"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", ">= 1.50"
  spec.add_development_dependency "timecop", ">= 0.9"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end