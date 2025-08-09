# frozen_string_literal: true

require 'active_record'
require 'yaml'
require 'erb'
require 'dotenv/load'
require 'fileutils'
require 'logger'

# Ensure the db directory exists
FileUtils.mkdir_p('db')

# Configure environment (development is default)
# RAILS_ENV takes precedence over RACK_ENV for consistency with Rails/RSpec
current_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
ENV['RACK_ENV'] = current_env

db_config_file = File.expand_path('database.yml', __dir__)
db_config = YAML.load(ERB.new(File.read(db_config_file)).result, aliases: true)

# TODO: ActiveRecord::Base.logger = Logger.new($stdout)
ActiveRecord::Base.establish_connection(db_config[current_env])
