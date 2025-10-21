module OptionsTrader
  module Services
    class DeltaEnricher
      include OptionsTrader::Loggable

      class Error < OptionsTrader::Error; end

      def initialize(predictor:)
        @predictor = predictor
      end

      def enrich(option_chain)
        logger.info("DeltaEnricher: Enriching option chain for #{option_chain.symbol}")

        enrich_calls(option_chain.call_opts, option_chain.underlying_price)
        enrich_puts(option_chain.put_opts, option_chain.underlying_price)

        enforce_parity(option_chain.call_opts, option_chain.put_opts, option_chain.underlying_price)

        option_chain
      end

      def enrich_batch(option_chains)
        option_chains.map { |chain| enrich(chain) }
      end

      private

      def enrich_calls(options, underlying_price)
        return if options.empty?

        logger.debug("DeltaEnricher: Predicting deltas for #{options.size} CALL options")

        payload = build_payload(options, 'CALL')
        result = @predictor.predict_deltas(payload)

        # Response structure: { predictions: [0.65, 0.45, ...], contract_type: 'CALL', model_version: '1.0.0', count: N }
        apply_deltas(options, result['predictions'])

        logger.debug("DeltaEnricher: Successfully predicted #{result['count']} CALL deltas using model #{result['model_version']}")
      end

      def enrich_puts(options, underlying_price)
        return if options.empty?

        logger.debug("DeltaEnricher: Predicting deltas for #{options.size} PUT options")

        payload = build_payload(options, 'PUT')
        result = @predictor.predict_deltas(payload)

        apply_deltas(options, result['predictions'])

        logger.debug("DeltaEnricher: Successfully predicted #{result['count']} PUT deltas using model #{result['model_version']}")
      end

      def build_payload(options, contract_type)
        validate_required_features(options, contract_type)

        {
          contract_type: contract_type,
          features: options.map do |opt|
            {
              dte: opt.days_to_expiration,
              moneyness: opt.has_feature?(:moneyness) ? opt.moneyness : opt.moneyness,
              mark: opt.mark,
              strike: opt.strike,
              underlying_price: opt.underlying_price,
              vix9d: opt.respond_to?(:vix9d) ? opt.vix9d : nil,
              vvix: opt.respond_to?(:vvix) ? opt.vvix : nil,
              skew: opt.respond_to?(:skew) ? opt.skew : nil
            }
          end,
          version: 'latest',
          smooth: true,
          interpolate: false
        }
      end

      def validate_required_features(options, contract_type)
        missing_features = []

        options.each_with_index do |opt, idx|
          if opt.days_to_expiration.nil?
            missing_features << "days_to_expiration missing for option at index #{idx} (strike: #{opt.strike})"
          end

          moneyness_value = opt.has_feature?(:moneyness) ? opt.moneyness : opt.moneyness
          if moneyness_value.nil?
            missing_features << "moneyness missing for option at index #{idx} (strike: #{opt.strike})"
          end

          if opt.mark.nil?
            missing_features << "mark missing for option at index #{idx} (strike: #{opt.strike})"
          end
          if opt.strike.nil? || opt.strike <= 0
            missing_features << "strike missing or invalid for option at index #{idx}"
          end
          if opt.underlying_price.nil? || opt.underlying_price <= 0
            missing_features << "underlying_price missing or invalid for option at index #{idx} (strike: #{opt.strike})"
          end

          # Check for dynamic features
          if !opt.respond_to?(:vix9d) || opt.vix9d.nil?
            missing_features << "vix9d missing for option at index #{idx} (strike: #{opt.strike})"
          end
          if !opt.respond_to?(:vvix) || opt.vvix.nil?
            missing_features << "vvix missing for option at index #{idx} (strike: #{opt.strike})"
          end
          if !opt.respond_to?(:skew) || opt.skew.nil?
            missing_features << "skew missing for option at index #{idx} (strike: #{opt.strike})"
          end
        end

        unless missing_features.empty?
          error_msg = "Required features missing for #{contract_type} delta prediction:\n#{missing_features.join("\n")}"
          logger.error(error_msg)
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

        logger.debug("DeltaEnricher: Enforcing put-call parity")

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

        logger.debug("DeltaEnricher: Put-call parity enforced around ATM strike #{atm_strike}")
      end
    end
  end
end
