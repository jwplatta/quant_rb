# frozen_string_literal: true

module QuantRb
  module Data
    class OptionChainConfig
      VALID_CHAIN_MODES = %i[synthetic sampled_interpolated sampled_validated].freeze
      VALID_PRICING_MODELS = %i[black_scholes binomial].freeze

      attr_reader :underlying, :option_root, :resolution, :provider, :chain_mode,
                  :pricing_model, :iv_proxy, :validation, :strike_grid, :raw_options

      def initialize(underlying:, option_root:, resolution:, provider:, chain_mode:, pricing_model:, iv_map:, validation:, strike_grid:, raw_options: {})
        @underlying = underlying
        @option_root = option_root
        @resolution = resolution
        @provider = provider
        @chain_mode = chain_mode.to_sym
        @pricing_model = normalize_pricing_model(pricing_model)
        @iv_proxy = normalize_iv_proxy(iv_map)
        @validation = validation&.to_sym || :repair
        @strike_grid = default_strike_grid.merge((strike_grid || {}).transform_keys(&:to_sym))
        @raw_options = raw_options || {}

        validate!
      end

      def synthetic?
        chain_mode == :synthetic
      end

      def sampled_interpolated?
        chain_mode == :sampled_interpolated
      end

      def sampled_validated?
        chain_mode == :sampled_validated
      end

      private

      def default_strike_grid
        {
          step: 5.0,
          range_ratio: 0.20
        }
      end

      def normalize_pricing_model(value)
        case value&.to_sym
        when nil, :black_scholes then :black_scholes
        when :binomial, :crr then :binomial
        else
          value.to_sym
        end
      end

      def normalize_iv_proxy(value)
        case value
        when nil
          nil
        when String, Symbol
          value.to_s
        when Hash
          raise ArgumentError, "Synthetic option chains support a single IV proxy ticker" if value.empty?

          value.values.first.to_s
        else
          raise ArgumentError, "Unsupported IV proxy #{value.inspect}"
        end
      end

      def validate!
        raise ArgumentError, "Unsupported chain mode: #{chain_mode}" unless VALID_CHAIN_MODES.include?(chain_mode)
        raise ArgumentError, "Unsupported pricing model: #{pricing_model}" unless VALID_PRICING_MODELS.include?(pricing_model)
        raise ArgumentError, "Synthetic option chains require an IV proxy ticker" if synthetic? && iv_proxy.to_s.strip.empty?
        raise ArgumentError, "Synthetic option chains require an underlying symbol" if synthetic? && underlying.to_s.strip.empty?
        return unless sampled_validated? && raw_options[:interpolate]

        raise ArgumentError, "sampled_validated mode cannot request interpolation"
      end
    end
  end
end
