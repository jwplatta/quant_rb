module OptionsTrader
  module Queries
    class OptionChainWithFeatures
      # Fetch option chain records enriched with additional price features
      #
      # @param underlying_symbol [String] The underlying symbol (e.g., '$SPX')
      # @param expiration_date [String, Date] The expiration date for options
      # @param end_time [String, Time] The end time for the query window
      # @param window_minutes [Integer] The window in minutes for LOCF lookup
      # @param contract_type [String] 'CALL' or 'PUT'
      # @param features [Hash] Optional features hash (e.g., { vix9d: '$VIX9D', skew: '$SKEW' })
      # @param source [String] Data source filter (default: 'polygon')
      # @return [Array<Hash>] Array of enriched option records
      def self.fetch(underlying_symbol:, expiration_date:, end_time:, window_minutes:,
                     contract_type:, features: {}, source: 'polygon')

        start_time = calculate_start_time(end_time, window_minutes)

        sql = build_sql(
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          end_time: end_time,
          start_time: start_time,
          contract_type: contract_type,
          features: features,
          source: source
        )

        ActiveRecord::Base.connection.execute(sql).to_a
      end

      def self.build_sql(underlying_symbol:, expiration_date:, end_time:, start_time:,
                         contract_type:, features:, source:)
        conn = ActiveRecord::Base.connection

        exp_date = conn.quote(expiration_date.to_s)
        end_t = conn.quote(end_time.to_s)
        start_t = conn.quote(start_time.to_s)
        contract = conn.quote(contract_type)
        src = conn.quote(source)

        <<~SQL
          WITH options AS (
            SELECT DISTINCT ON (symbol)
              symbol,
              (expiration_date::date - valid_time::date) AS dte,
              strike,
              contract_type,
              expiration_date,
              mark,
              underlying_price,
              volume,
              open_price,
              close_price,
              high_price,
              low_price,
              valid_time
            FROM option_chain_history
            WHERE expiration_date = #{exp_date}
              AND valid_time <= #{end_t}
              AND valid_time > #{start_t}
              AND contract_type = #{contract}
              AND source = #{src}
            ORDER BY symbol, valid_time DESC
          )
          SELECT
            options.symbol,
            options.strike,
            options.contract_type,
            options.expiration_date,
            options.mark,
            options.volume,
            options.open_price,
            options.close_price,
            options.high_price,
            options.low_price,
            options.valid_time,
            options.dte,
            underlying.close as underlying_price,
            #{moneyness_select(contract_type)} as moneyness#{feature_selects(features)}
          FROM options
          #{underlying_join(underlying_symbol)}#{feature_joins(features)}
          WHERE #{moneyness_where(contract_type)}
          ORDER BY options.strike
        SQL
      end

      private

      def self.calculate_start_time(end_time, window_minutes)
        time = end_time.is_a?(String) ? Time.parse(end_time) : end_time
        (time - (window_minutes * 60)).strftime('%Y-%m-%d %H:%M:%S')
      end

      def self.moneyness_select(contract_type)
        case contract_type.upcase
        when 'PUT'
          'options.strike / underlying.close::float'
        when 'CALL'
          'underlying.close::float / options.strike'
        else
          raise ArgumentError, "Invalid contract_type: #{contract_type}. Must be 'CALL' or 'PUT'"
        end
      end

      # REVIEW: we might want to make this optional
      def self.moneyness_where(contract_type)
        "#{moneyness_select(contract_type)} <= 1.01"
      end

      def self.feature_selects(features)
        return '' if features.empty?

        features.map { |alias_name, _symbol| ",\n            #{alias_name}.close as #{alias_name}" }.join
      end

      def self.feature_joins(features)
        return '' if features.empty?

        "\n" + features.map { |alias_name, symbol| lateral_join(alias_name, symbol) }.join("\n")
      end

      def self.underlying_join(underlying_symbol)
        <<~SQL.chomp
          LEFT JOIN LATERAL (
            SELECT close, valid_time
            FROM price_history
            WHERE symbol = '#{sanitize_symbol(underlying_symbol)}'
              AND valid_time <= options.valid_time
            ORDER BY valid_time DESC
            LIMIT 1
          ) underlying ON true
        SQL
      end

      def self.lateral_join(alias_name, symbol)
        <<~SQL.chomp
          LEFT JOIN LATERAL (
            SELECT close, valid_time
            FROM price_history
            WHERE symbol = '#{sanitize_symbol(symbol)}'
              AND valid_time <= options.valid_time
            ORDER BY valid_time DESC
            LIMIT 1
          ) #{alias_name} ON true
        SQL
      end

      def self.sanitize_symbol(symbol)
        # Prevent SQL injection by validating symbol format
        # Valid symbols are alphanumeric with optional $ prefix
        raise ArgumentError, "Invalid symbol: #{symbol}" unless symbol.match?(/\A\$?[A-Z0-9]+\z/i)
        symbol
      end
    end
  end
end
