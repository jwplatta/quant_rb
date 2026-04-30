# frozen_string_literal: true

module QuantRb
  module Data
    class OptionChainConfig
      VALID_CHAIN_MODES = %i[synthetic sampled_interpolated sampled_validated].freeze
      VALID_PRICING_MODELS = %i[black_scholes binomial].freeze

      attr_reader :underlying, :option_root, :resolution, :provider, :chain_mode,
                  :pricing_model, :iv_map, :validation, :strike_grid, :raw_options

      def initialize(underlying:, option_root:, resolution:, provider:, chain_mode:, pricing_model:, iv_map:, validation:, strike_grid:, raw_options: {})
        @underlying = underlying
        @option_root = option_root
        @resolution = resolution
        @provider = provider
        @chain_mode = chain_mode.to_sym
        @pricing_model = normalize_pricing_model(pricing_model)
        @iv_map = normalize_iv_map(iv_map)
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

      def iv_proxy_for_dte(days_to_expiration)
        return nil if iv_map.empty?

        entry = iv_map.find { |threshold, _| days_to_expiration <= threshold }
        (entry || iv_map.to_a.last)&.last
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

      def normalize_iv_map(value)
        return {} if value.nil?

        value.each_with_object([]) do |(raw_key, ticker), entries|
          threshold =
            case raw_key.to_s.upcase
            when /\A(\d+)DTE\z/
              Regexp.last_match(1).to_i
            when "ODTE", "0DTE"
              0
            else
              raise ArgumentError, "Unsupported IV bucket #{raw_key.inspect}"
            end

          entries << [threshold, ticker]
        end.sort_by(&:first).to_h
      end

      def validate!
        raise ArgumentError, "Unsupported chain mode: #{chain_mode}" unless VALID_CHAIN_MODES.include?(chain_mode)
        raise ArgumentError, "Unsupported pricing model: #{pricing_model}" unless VALID_PRICING_MODELS.include?(pricing_model)
        raise ArgumentError, "Synthetic option chains require IV mapping" if synthetic? && iv_map.empty?
        raise ArgumentError, "Synthetic option chains require an underlying symbol" if synthetic? && underlying.to_s.strip.empty?
        return unless sampled_validated? && raw_options[:interpolate]

        raise ArgumentError, "sampled_validated mode cannot request interpolation"
      end
    end
  end
end
