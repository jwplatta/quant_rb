# frozen_string_literal: true

require "yaml"
require "tickrake"

module QuantRb
  module Data
    class DataSourcesRegistry
      UnderlyingConfig = Struct.new(:symbol, :provider, :kind, keyword_init: true)
      OptionChainDefaults = Struct.new(
        :option_root,
        :underlying,
        :provider,
        :default_mode,
        :default_pricing_model,
        keyword_init: true
      )
      ResolvedOptionChain = Struct.new(:subscription, :config, keyword_init: true)

      def self.load(path: QuantRb.config.data_sources_config_path)
        new(path: path).load
      end

      def initialize(path:)
        @path = File.expand_path(path.to_s)
      end

      def load
        raw = YAML.safe_load(File.read(@path), permitted_classes: [Date, Symbol], aliases: true) || {}
        tickrake = raw.fetch("tickrake", {})
        tickrake_config_path = File.expand_path(tickrake.fetch("config_path", Tickrake::PathSupport.config_path).to_s)
        tickrake_config = Tickrake::ConfigLoader.load(tickrake_config_path)
        securities = load_underlyings(raw.fetch("securities", {}), kind: :security, tickrake_config:)
        indices = load_underlyings(raw.fetch("indices", {}), kind: :index, tickrake_config:)
        option_chains = load_option_chains(
          raw.fetch("option_chains", {}),
          tickrake_config:,
          underlyings: securities.merge(indices)
        )

        Loaded.new(
          path: @path,
          tickrake_config_path:,
          tickrake_config:,
          securities:,
          indices:,
          option_chains:
        )
      rescue Errno::ENOENT
        raise QuantRb::Error, "QuantRb data-sources config not found at #{@path}"
      rescue Psych::SyntaxError => e
        raise QuantRb::Error, "Invalid QuantRb data-sources config at #{@path}: #{e.message}"
      end

      class Loaded
        attr_reader :path, :tickrake_config_path, :tickrake_config, :securities, :indices, :option_chains

        def initialize(path:, tickrake_config_path:, tickrake_config:, securities:, indices:, option_chains:)
          @path = path
          @tickrake_config_path = tickrake_config_path
          @tickrake_config = tickrake_config
          @securities = securities
          @indices = indices
          @option_chains = option_chains
        end

        def resolve_underlying(subscription)
          symbol = subscription.fetch(:symbol).to_s.upcase
          config = if subscription.fetch(:kind).to_sym == :index
                     indices[symbol]
                   else
                     securities[symbol]
                   end
          raise QuantRb::Error, "No configured #{subscription.fetch(:kind)} data source for #{symbol} in #{path}" unless config

          subscription.merge(symbol: symbol, provider: config.provider, kind: config.kind)
        end

        def resolve_option_chain(subscription)
          option_root = subscription.fetch(:option_root).to_s.upcase
          defaults = option_chains[option_root]
          raise QuantRb::Error, "No configured option chain data source for #{option_root} in #{path}" unless defaults

          requested_underlying = subscription.fetch(:underlying).to_s.upcase
          if requested_underlying != defaults.underlying
            raise QuantRb::Error,
                  "Configured underlying for #{option_root} is #{defaults.underlying}, got #{requested_underlying}"
          end

          underlying_entry = indices[requested_underlying] || securities[requested_underlying]
          raise QuantRb::Error, "No configured underlying data source for #{requested_underlying} in #{path}" unless underlying_entry

          requested_mode = subscription[:chain_mode]
          requested_pricing_model = subscription[:pricing_model]
          config = QuantRb::Data::OptionChainConfig.new(
            underlying: requested_underlying,
            option_root: option_root,
            resolution: subscription.fetch(:resolution),
            provider: defaults.provider,
            underlying_provider: underlying_entry.provider,
            chain_mode: requested_mode || defaults.default_mode || :sampled_validated,
            pricing_model: requested_pricing_model || defaults.default_pricing_model || :black_scholes,
            iv_map: subscription[:iv_map],
            validation: subscription[:validation],
            strike_grid: subscription[:strike_grid] || {},
            raw_options: subscription[:raw_options] || {},
            market_timezone: subscription[:market_timezone]
          )

          ResolvedOptionChain.new(
            subscription: subscription.merge(
              underlying: requested_underlying,
              option_root: option_root,
              provider: defaults.provider,
              underlying_provider: underlying_entry.provider
            ),
            config:
          )
        end
      end

      private

      def load_underlyings(mapping, kind:, tickrake_config:)
        raise QuantRb::Error, "#{kind}s must be a mapping" unless mapping.is_a?(Hash)

        mapping.each_with_object({}) do |(symbol, attrs), result|
          raise QuantRb::Error, "#{kind} #{symbol} config must be a mapping" unless attrs.is_a?(Hash)

          provider = attrs.fetch("provider").to_s
          validate_provider!(provider, tickrake_config:)
          result[symbol.to_s.upcase] = UnderlyingConfig.new(symbol: symbol.to_s.upcase, provider:, kind:)
        end
      end

      def load_option_chains(mapping, tickrake_config:, underlyings:)
        raise QuantRb::Error, "option_chains must be a mapping" unless mapping.is_a?(Hash)

        mapping.each_with_object({}) do |(option_root, attrs), result|
          raise QuantRb::Error, "option chain #{option_root} config must be a mapping" unless attrs.is_a?(Hash)

          provider = attrs.fetch("provider").to_s
          validate_provider!(provider, tickrake_config:)
          underlying = attrs.fetch("underlying").to_s.upcase
          raise QuantRb::Error, "option chain #{option_root} references unknown underlying #{underlying}" unless underlyings.key?(underlying)

          result[option_root.to_s.upcase] = OptionChainDefaults.new(
            option_root: option_root.to_s.upcase,
            underlying:,
            provider:,
            default_mode: normalize_mode(attrs["default_mode"]),
            default_pricing_model: normalize_pricing_model(attrs["default_pricing_model"])
          )
        end
      end

      def validate_provider!(provider, tickrake_config:)
        tickrake_config.provider_definition(provider)
      rescue Tickrake::ConfigError => e
        raise QuantRb::Error, e.message
      end

      def normalize_mode(value)
        return nil if value.nil?

        value.to_sym
      end

      def normalize_pricing_model(value)
        return nil if value.nil?

        value.to_sym
      end
    end
  end
end
