# frozen_string_literal: true

require 'rspec'
require 'timecop'
require 'json'
require_relative '../../../mixins/schwab/option_chain_cache'
require_relative '../../../mixins/schwab/data_objects/option_chain'

RSpec.describe Schwab::OptionChainCache do
  # Create a test class that includes the OptionChainCache directly
  let(:test_class) do
    Class.new do
      # Manually add the class methods
      extend Schwab::OptionChainCache::ClassMethods

      # Then include the module for instance methods
      include Schwab::OptionChainCache

      # Implement required original_option_chain method
      def original_option_chain(symbol, **options)
        # Track calls to this method
        (@call_count ||= 0)
        @call_count += 1

        # Return mock option chain from fixture
        data = JSON.parse(File.read("spec/fixtures/option_chains/#{symbol}.json"), symbolize_names: true)
        DataObjects::OptionChain.build(data)
      end

      # Helper method to expose call count for testing
      def call_count
        @call_count || 0
      end
    end
  end

  let(:instance) { test_class.new }

  before do
    # Clear cache before each test
    test_class.clear_option_chain_cache
  end
  
  describe '#cached_option_chain' do
    context 'with default TTL' do
      it 'caches the option chain' do
        # First call should fetch from original method
        chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
        expect(chain1).to be_an_instance_of(DataObjects::OptionChain)
        expect(instance.call_count).to eq(1)
        
        # Second call should use cached version
        chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
        expect(chain2).to be_an_instance_of(DataObjects::OptionChain)
        expect(instance.call_count).to eq(1) # Call count should not increase
        
        # Different params should result in a new fetch
        chain3 = instance.cached_option_chain('ACME_calls', contract_type: 'PUT', strike_range: 'OTM')
        expect(chain3).to be_an_instance_of(DataObjects::OptionChain)
        expect(instance.call_count).to eq(2) # Call count should increase
      end
      
      it 'expires the cache after the TTL' do
        # Set a short TTL for testing
        chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 10)
        expect(instance.call_count).to eq(1)
        
        # Call again within TTL
        chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 10)
        expect(instance.call_count).to eq(1) # No new call
        
        # Advance time beyond TTL
        Timecop.freeze(Time.now + 11) do
          chain3 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 10)
          expect(instance.call_count).to eq(2) # Should make a new call
        end
      end
    end
    
    context 'with custom TTL' do
      it 'respects a custom TTL value' do
        # Set a custom TTL
        chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 30)
        expect(instance.call_count).to eq(1)
        
        # Advance time but stay within TTL
        Timecop.freeze(Time.now + 20) do
          chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 30)
          expect(instance.call_count).to eq(1) # No new call, still cached
        end
        
        # Advance time beyond TTL
        Timecop.freeze(Time.now + 31) do
          chain3 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM', ttl: 30)
          expect(instance.call_count).to eq(2) # Should make a new call
        end
      end
    end
  end
  
  describe '#invalidate_option_chain' do
    it 'allows manual invalidation of a specific cache entry' do
      # First call to cache
      chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance.call_count).to eq(1)
      
      # Invalidate the specific cache entry
      instance.invalidate_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      
      # Next call should fetch fresh data
      chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance.call_count).to eq(2)
    end
    
    it 'only invalidates the specific cache entry' do
      # Create two different cache entries
      chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'PUT', strike_range: 'OTM')
      expect(instance.call_count).to eq(2)
      
      # Invalidate only one entry
      instance.invalidate_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      
      # The invalidated entry should be refetched
      chain3 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance.call_count).to eq(3)
      
      # The non-invalidated entry should still be cached
      chain4 = instance.cached_option_chain('ACME_calls', contract_type: 'PUT', strike_range: 'OTM')
      expect(instance.call_count).to eq(3) # No increase
    end
  end
  
  describe '#clear_option_chain_cache' do
    it 'clears the entire cache' do
      # Cache multiple entries
      chain1 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      chain2 = instance.cached_option_chain('ACME_calls', contract_type: 'PUT', strike_range: 'OTM')
      expect(instance.call_count).to eq(2)
      
      # Clear the entire cache
      instance.clear_option_chain_cache
      
      # All entries should be refetched
      chain3 = instance.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      chain4 = instance.cached_option_chain('ACME_calls', contract_type: 'PUT', strike_range: 'OTM')
      expect(instance.call_count).to eq(4)
    end
  end
  
  describe 'class-level cache operations' do
    it 'allows class-level cache invalidation' do
      # Create an instance and cache some data
      instance1 = test_class.new
      chain1 = instance1.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance1.call_count).to eq(1)
      
      # Invalidate at class level
      test_class.invalidate_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      
      # Create a new instance - should refetch the data
      instance2 = test_class.new
      chain2 = instance2.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance2.call_count).to eq(1) # First call for this instance
    end
    
    it 'shares cache across instances' do
      # First instance caches data
      instance1 = test_class.new
      chain1 = instance1.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance1.call_count).to eq(1)
      
      # Second instance should use cached data
      instance2 = test_class.new
      chain2 = instance2.cached_option_chain('ACME_calls', contract_type: 'CALL', strike_range: 'OTM')
      expect(instance2.call_count).to eq(0) # Should not call original_option_chain
    end
  end
end