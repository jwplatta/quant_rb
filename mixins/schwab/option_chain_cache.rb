# frozen_string_literal: true

module Schwab
  module OptionChainCache
    def self.included(base)
      base.extend(ClassMethods)

      # When included in a module, also extend the module itself
      # This handles the case where Schwab is a module, not a class
      if base.instance_of?(Module)
        base.singleton_class.extend(ClassMethods)
      end
    end

    module ClassMethods
      def option_chain_cache
        @option_chain_cache ||= {}
      end

      def clear_option_chain_cache
        @option_chain_cache = {}
      end

      def invalidate_option_chain(symbol, options = {})
        cache_key = [symbol, options].hash
        option_chain_cache.delete(cache_key)
      end

      def option_chain_timestamps
        @option_chain_timestamps ||= {}
      end
    end

    def option_chain_cache
      self.class.option_chain_cache
    end

    def option_chain_timestamps
      self.class.option_chain_timestamps
    end

    def invalidate_option_chain(symbol, options = {})
      self.class.invalidate_option_chain(symbol, options)
    end

    def clear_option_chain_cache
      self.class.clear_option_chain_cache
    end

    # Add TTL support to automatically expire entries
    def cached_option_chain(symbol, **options)
      # Extract TTL if provided, default to 1 minute
      ttl = options.delete(:ttl) || 60
      cache_key = [symbol, options].hash

      # Check if entry exists and if it's expired
      if option_chain_cache.key?(cache_key) && option_chain_timestamps.key?(cache_key)
        timestamp = option_chain_timestamps[cache_key]
        if Time.now - timestamp > ttl
          option_chain_cache.delete(cache_key)
          option_chain_timestamps.delete(cache_key)
        else
          return option_chain_cache[cache_key]
        end
      end

      result = original_option_chain(symbol, **options)
      option_chain_cache[cache_key] = result
      option_chain_timestamps[cache_key] = Time.now
      result
    end
  end
end
