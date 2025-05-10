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
ENV['RACK_ENV'] ||= 'development'

# Load database configuration from config/database.yml
db_config_file = File.expand_path('database.yml', __dir__)
db_config = YAML.load(ERB.new(File.read(db_config_file)).result, aliases: true)

# Set up the database connection
ActiveRecord::Base.logger = Logger.new($stdout)
ActiveRecord::Base.establish_connection(db_config[ENV['RACK_ENV']])

# Require model files
Dir["#{File.dirname(__FILE__)}/../models/*.rb"].each { |file| require file }
