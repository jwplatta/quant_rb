require_relative 'transform/monotonicity_enforcer'
require_relative 'transform/strike_adder'
require_relative 'transform/linear_interpolator'

module OptionsTrader
  module SyntheticData
    class OptionChainPipeline
      class PipelineStateError < StandardError; end
      class MissingContextError < StandardError; end

      # Initialize the pipeline with an option chain and context metadata
      #
      # @param option_chain [DataObjects::OptionsChain] The raw option chain to transform
      # @option context [Float] :underlying_price Current underlying price
      # @option context [Integer] :dte Days to expiration
      # @option context [Date] :expiration_date Option expiration date
      # @option context [String] :underlying_symbol Underlying symbol (e.g., 'SPXW')
      # @option context [Time] :valid_time Timestamp for historical snapshot (optional)
      def initialize(option_chain)
        @original_chain = option_chain
        @calls = option_chain.call_opts.dup
        @puts = option_chain.put_opts.dup
        @features = {}
        @pipeline_started = false
        @features_set = false

      end

      # Add market features to be propagated to synthetic options
      # This method MUST be called before any transformations
      #
      # @param features [Hash] Feature values (e.g., { vix9d: 18.5, vvix: 95.2 })
      # @return [self] For method chaining
      def with_features(features = {})
        if @pipeline_started
          raise PipelineStateError, ".with_features must be called before any transformations"
        end

        @features = features
        @features_set = true
        self
      end

      # Enforce no-arbitrage monotonicity constraints on option prices
      # - Calls: prices decrease with increasing strike
      # - Puts: prices increase with increasing strike
      #
      # @param method [String] 'adjust' (fix violations) or 'remove' (set violating prices to nil)
      # @return [self] For method chaining
      def enforce_monotonicity(method: 'remove')
        start_pipeline!

        @calls = Transform::MonotonicityEnforcer.enforce(@calls, method: method)
        @puts = Transform::MonotonicityEnforcer.enforce(@puts, method: method)

        self
      end

      # Add synthetic options for missing strikes in the chain
      # Generates strikes with dense ATM spacing and wider OTM spacing
      #
      # @param min_strike [Float, nil] Minimum strike (optional, uses offset if nil)
      # @param max_strike [Float, nil] Maximum strike (optional, uses offset if nil)
      # @param min_offset [Integer] Offset below underlying for min strike (default: -3000)
      # @param max_offset [Integer] Offset above underlying for max strike (default: 1000)
      # @param inner_offset [Integer] ATM range for dense strikes (default: 225)
      # @param inner_step [Integer] Strike spacing within ATM range (default: 5)
      # @param outer_step [Integer] Strike spacing outside ATM range (default: 25)
      # @return [self] For method chaining
      def complete_strikes(
        min_strike: nil,
        max_strike: nil,
        min_offset: Transform::StrikeAdder::DEFAULT_MIN_OFFSET,
        max_offset: Transform::StrikeAdder::DEFAULT_MAX_OFFSET,
        inner_offset: Transform::StrikeAdder::DEFAULT_INNER_OFFSET,
        inner_step: Transform::StrikeAdder::DEFAULT_INNER_STEP,
        outer_step: Transform::StrikeAdder::DEFAULT_OUTER_STEP
      )
        start_pipeline!

        result = Transform::StrikeAdder.add_strikes(
          calls: @calls,
          put_opts: @puts,
          features: @features,
          min_strike: min_strike,
          max_strike: max_strike,
          min_offset: min_offset,
          max_offset: max_offset,
          inner_offset: inner_offset,
          inner_step: inner_step,
          outer_step: outer_step
        )

        @calls = result[:calls]
        @puts = result[:put_opts]

        self
      end

      # Interpolate missing option prices using linear interpolation
      # Assumes prices are already monotonic (will raise error if not)
      # Handles ITM and OTM options differently:
      # - OTM: Interpolates mark directly (mark = extrinsic)
      # - ITM: Interpolates extrinsic value, then calculates mark (mark = extrinsic + intrinsic)
      #
      # @param min_extrinsic [Float] Minimum extrinsic value (default: 0.025)
      # @return [self] For method chaining
      def interpolate_prices(min_extrinsic: 0.025)
        start_pipeline!

        @calls = Transform::LinearInterpolator.interpolate(
          @calls,
          contract_type: 'CALL',
          min_extrinsic: min_extrinsic
        )

        @puts = Transform::LinearInterpolator.interpolate(
          @puts,
          contract_type: 'PUT',
          min_extrinsic: min_extrinsic
        )

        Validators::Monotonicity.check(@calls)
        Validators::Monotonicity.check(@puts)

        self
      end

      # Build and return the transformed option chain
      #
      # @return [DataObjects::OptionsChain] The transformed option chain
      def build
        DataObjects::OptionsChain.new(
          symbol: @original_chain.symbol,
          underlying_price: @original_chain.underlying_price,
          call_opts: @calls,
          put_opts: @puts
        )
      end

      private

      def start_pipeline!
        @pipeline_started = true
      end
    end
  end
end
