module OptionsTrader
  module Services
    class DeltaEnricher
      class Error < OptionsTrader::Error; end

      def initialize(predictor:)
        @predictor = predictor
      end

      def enrich(option_chain, features={})
        enrich_calls(option_chain.call_opts, features)
        enrich_puts(option_chain.put_opts, features)

        # REVIEW: temporarily disabling because it causes monotonicity violations
        # enforce_parity(option_chain.call_opts, option_chain.put_opts, option_chain.underlying_price)

        option_chain
      end

      def enrich_batch(option_chains, features={})
        option_chains.map { |chain| enrich(chain, features) }
      end

      private

      def enrich_calls(options, features={})
        return if options.empty?

        payload = build_payload(options, features)
        result = @predictor.predict_deltas(payload)

        # Response structure: { predictions: [0.65, 0.45, ...], contract_type: 'CALL', model_version: '1.0.0', count: N }
        apply_deltas(options, result['predictions'])
      end

      def enrich_puts(options, features={})
        return if options.empty?

        payload = build_payload(options, features)

        result = @predictor.predict_deltas(payload)

        apply_deltas(options, result['predictions'])
      end

      def build_payload(options, features)
        opt_features = options.map do |opt|
          {
            dte: opt.days_to_expiration,
            moneyness: opt.moneyness,
            mark: opt.mark,
            strike: opt.strike,
            underlying_price: opt.underlying_price
          }.merge(features)
        end

        validate_required_features(opt_features)

        {
          contract_type: options.first.put_call,
          features: opt_features,
          version: 'latest',
          smooth: true,
          interpolate: false
        }
      end

      def validate_required_features(features)
        missing_features = []

        features.each_with_index do |feature, idx|
          if feature[:dte].nil?
            missing_features << "days_to_expiration missing for option at index #{idx} (strike: #{feature[:strike]})"
          end
          if feature[:mark].nil?
            missing_features << "mark missing for option at index #{idx} (strike: #{feature[:strike]})"
          end
          if feature[:strike].nil? || feature[:strike] <= 0
            missing_features << "strike missing or invalid for option at index #{idx}"
          end
          if feature[:underlying_price].nil? || feature[:underlying_price] <= 0
            missing_features << "underlying_price missing or invalid for option at index #{idx} (strike: #{feature[:strike]})"
          end

          if feature[:vix9d].nil?
            missing_features << "vix9d missing for option at index #{idx} (strike: #{feature[:strike]})"
          end
          if feature[:vvix].nil?
            missing_features << "vvix missing for option at index #{idx} (strike: #{feature[:strike]})"
          end
        end

        unless missing_features.empty?
          error_msg = "Required features missing for prediction:\n#{missing_features.join("\n")}"
          raise Error, error_msg
        end
      end

      def apply_deltas(options, predictions)
        options.each_with_index do |opt, idx|
          opt.delta = predictions[idx]
        end
      end

      # Enforce put-call parity:
      # - Use OTM PUT deltas to calculate ITM CALL deltas
      # - Use OTM CALL deltas to calculate ITM PUT deltas
      # - Smooth around ATM strikes for consistency
      def enforce_parity(call_opts, put_opts, underlying_price)
        return if call_opts.empty? || put_opts.empty?

        call_opts_by_strike = call_opts.index_by(&:strike)
        put_opts_by_strike = put_opts.index_by(&:strike)

        # Find ATM strike (closest to underlying price)
        all_strikes = (call_opts.map(&:strike) + put_opts.map(&:strike)).uniq.sort
        atm_strike = all_strikes.min_by { |strike| (strike - underlying_price).abs }

        all_strikes.each do |strike|
          call_opt = call_opts_by_strike[strike]
          put_opt = put_opts_by_strike[strike]

          next unless call_opt && put_opt

          if strike < underlying_price
            # ITM call, OTM put - use PUT delta to calculate CALL delta
            # Put-call parity: delta_call = delta_put + 1
            if put_opt.delta
              call_opt.delta = put_opt.delta + 1.0
            end
          elsif strike > underlying_price
            # OTM call, ITM put - use CALL delta to calculate PUT delta
            # Put-call parity: delta_put = delta_call - 1
            if call_opt.delta
              put_opt.delta = call_opt.delta - 1.0
            end
          else
            # ATM strike - average the model predictions if both exist
            if call_opt.delta && put_opt.delta
              # ATM call delta should be ~0.5, ATM put delta should be ~-0.5
              avg_abs_delta = (call_opt.delta.abs + put_opt.delta.abs) / 2.0
              call_opt.delta = avg_abs_delta
              put_opt.delta = -avg_abs_delta
            end
          end
        end
      end
    end
  end
end
