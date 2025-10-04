module OptionsTrader
  module Utils
    module PCHIPInterpolator
      def self.interpolate(strike_deltas, target_strike, option_type = 'CALL')
        strikes = strike_deltas.keys.sort
        deltas = strikes.map { |s| strike_deltas[s] }

        # Clamp input deltas to valid range
        deltas = deltas.map { |d| clamp_delta(d, option_type) }

        # Boundary cases
        return deltas.first if target_strike <= strikes.first
        return deltas.last if target_strike >= strikes.last

        # Find segment
        idx = strikes.bsearch_index { |s| s > target_strike }
        return deltas.last if idx.nil? || idx >= strikes.size
        return deltas.first if idx == 0

        # Get segment endpoints
        x0, x1 = strikes[idx-1], strikes[idx]
        y0, y1 = deltas[idx-1], deltas[idx]

        # Calculate monotonic slopes
        m0 = compute_monotonic_slope(strikes, deltas, idx-1)
        m1 = compute_monotonic_slope(strikes, deltas, idx)

        # Hermite interpolation
        t = (target_strike - x0).to_f / (x1 - x0)
        h = x1 - x0

        h00 = 2*t**3 - 3*t**2 + 1
        h10 = t**3 - 2*t**2 + t
        h01 = -2*t**3 + 3*t**2
        h11 = t**3 - t**2

        result = h00*y0 + h10*h*m0 + h01*y1 + h11*h*m1

        # Clamp final result
        clamp_delta(result, option_type)
      end

      def self.compute_monotonic_slope(strikes, deltas, idx)
        n = strikes.size

        # Boundary conditions
        if idx == 0
          # Left boundary - forward difference
          h = strikes[1] - strikes[0]
          return (deltas[1] - deltas[0]) / h
        elsif idx == n - 1
          # Right boundary - backward difference
          h = strikes[idx] - strikes[idx-1]
          return (deltas[idx] - deltas[idx-1]) / h
        end

        # Interior point - use three-point stencil
        h1 = strikes[idx] - strikes[idx-1]
        h2 = strikes[idx+1] - strikes[idx]
        s1 = (deltas[idx] - deltas[idx-1]) / h1
        s2 = (deltas[idx+1] - deltas[idx]) / h2

        # Check for monotonicity violation
        if s1 * s2 <= 0
          # Sign change = local extremum, use zero slope
          return 0.0
        end

        # Weighted harmonic mean (preserves monotonicity better)
        # This is the PCHIP formula
        w1 = 2*h2 + h1
        w2 = h2 + 2*h1

        return (w1 + w2) / (w1/s1 + w2/s2)
      end

      def self.clamp_delta(delta, option_type)
        case option_type
        when 'CALL'
          [[delta, 0.0].max, 1.0].min  # Clamp to [0, 1]
        when 'PUT'
          [[delta, -1.0].max, 0.0].min  # Clamp to [-1, 0]
        else
          delta
        end
      end
    end
  end
end