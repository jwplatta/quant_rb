# frozen_string_literal: true

require 'rake'

# Load tasks first before loading environment
Dir.glob('lib/tasks/**/*.rake').each { |r| import r }

# Only load environment when needed for specific tasks
task :environment do
  require_relative 'config/environment'
end

namespace :db do
  task init: :environment
  task migrate: :environment
  task reset: :environment
  task drop: :environment
  task schema: :environment
end

namespace :persistence do
  task test: :environment
  task example: :environment
end
