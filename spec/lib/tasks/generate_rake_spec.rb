require 'spec_helper'
require 'rake'

RSpec.describe 'generate rake tasks' do
  before do
    Rake.application.rake_require 'tasks/generate'
    Rake::Task.define_task(:environment)
  end

  describe 'generate:migration' do
    let(:task) { Rake::Task['generate:migration'] }
    
    before do
      task.reenable
      allow(File).to receive(:write)
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 1, 12, 0, 0))
    end

    context 'with valid migration name' do
      it 'creates migration file with valid name' do
        ENV['NAME'] = 'create_users'
        expect(File).to receive(:write).with(
          'db/migrate/20240101120000_create_users.rb',
          /class CreateUsers < ActiveRecord::Migration/
        )
        expect { task.invoke }.to output(/Created migration/).to_stdout
      end

      it 'handles underscored names' do
        ENV['NAME'] = 'add_index_to_users'
        expect(File).to receive(:write).with(
          'db/migrate/20240101120000_add_index_to_users.rb',
          /class AddIndexToUsers < ActiveRecord::Migration/
        )
        expect { task.invoke }.to output(/Created migration/).to_stdout
      end
    end

    context 'with invalid migration name' do
      it 'rejects names with special characters' do
        ENV['NAME'] = 'create-users'
        expect { task.invoke }.to output(/Invalid migration name/).to_stdout.and raise_error(SystemExit)
      end

      it 'rejects names starting with numbers' do
        ENV['NAME'] = '123_create_users'
        expect { task.invoke }.to output(/Invalid migration name/).to_stdout.and raise_error(SystemExit)
      end

      it 'rejects empty names' do
        ENV['NAME'] = ''
        expect { task.invoke }.to output(/Invalid migration name/).to_stdout.and raise_error(SystemExit)
      end
    end

    context 'without NAME parameter' do
      it 'shows usage message' do
        ENV['NAME'] = nil
        expect { task.invoke }.to output(/Usage: rake generate:migration/).to_stdout.and raise_error(SystemExit)
      end
    end

    after do
      ENV['NAME'] = nil
    end
  end
end