# indicators.rb
#
# This module computes structural option-market indicators from
# raw option-chain rows (like your CSV).
#
# Each metric answers a DIFFERENT trading question:
#
# - Call GEX / Put GEX:
#     "Where does convexity pressure exist on each side?"
#
# - Net GEX:
#     "Are dealers stabilizing price or amplifying moves at this strike?"
#
# - Velocity Risk:
#     "If price gets here, how fast can it move before I can react?"
#
# These are NOT interchangeable metrics.

module Indicators
  # ------------------------------------------------------------
  # Utility helpers
  # ------------------------------------------------------------

  # Restrict analysis to strikes near spot (critical for signal quality)
  def self.window_rows(rows, spot:, width:)
    rows.select do |r|
      r[:strike] >= spot - width && r[:strike] <= spot + width
    end
  end

  # Group option rows by strike
  def self.group_by_strike(rows)
    rows.group_by { |r| r[:strike] }.sort.to_h
  end

  # ------------------------------------------------------------
  # Gamma Exposure (GEX)
  # ------------------------------------------------------------
  #
  # GEX answers:
  #   "Are dealers likely to STABILIZE price (positive gamma)
  #    or AMPLIFY price moves (negative gamma) at this strike?"
  #
  # Convention:
  # - Dealers assumed short options
  # - Short CALL  -> negative dealer gamma
  # - Short PUT   -> positive dealer gamma
  #

  # -------------------------
  # Call-side GEX (bars)
  #
  # Question answered:
  #   "How much UPSIDE convexity pressure exists here from calls?"
  #
  def self.call_gex(rows, spot:, window: 250)
    rows = window_rows(rows, spot: spot, width: window)

    group_by_strike(rows).transform_values do |strike_rows|
      call_gamma = strike_rows.sum do |r|
        r[:contract_type] == "CALL" ? r[:gamma] * r[:open_interest] : 0.0
      end

      # Standard GEX scaling
      call_gamma * (spot**2) * 0.01
    end
  end

  # -------------------------
  # Put-side GEX (bars)
  #
  # Question answered:
  #   "How much DOWNSIDE convexity pressure exists here from puts?"
  #
  def self.put_gex(rows, spot:, window: 250)
    rows = window_rows(rows, spot: spot, width: window)

    group_by_strike(rows).transform_values do |strike_rows|
      put_gamma = strike_rows.sum do |r|
        r[:contract_type] == "PUT" ? r[:gamma] * r[:open_interest] : 0.0
      end

      put_gamma * (spot**2) * 0.01
    end
  end

  # -------------------------
  # Net GEX (black line)
  #
  # Question answered:
  #   "Net-net, are dealers stabilizing price or amplifying moves here?"
  #
  # Positive  -> dealer hedging dampens moves (mean reversion)
  # Negative  -> dealer hedging reinforces moves (trend acceleration)
  #
  def self.net_gex(rows, spot:, window: 250)
    call = call_gex(rows, spot: spot, window: window)
    put  = put_gex(rows,  spot: spot, window: window)

    strikes = (call.keys + put.keys).uniq

    strikes.each_with_object({}) do |k, acc|
      acc[k] = (put[k] || 0.0) - (call[k] || 0.0)
    end
  end

  # ------------------------------------------------------------
  # Velocity Risk
  # ------------------------------------------------------------
  #
  # Velocity Risk answers:
  #   "If price enters this strike region, how FAST can it move
  #    before I can adjust?"
  #
  # This is a MAGNITUDE metric (non-directional).
  #
  # It combines:
  # - Delta slope   -> how fast hedging pressure increases
  # - Gamma         -> how non-linear the response becomes
  #
  # High velocity risk zones are BAD places to be short options.
  #

  # -------------------------
  # Velocity Risk Curve
  #
  def self.velocity_risk(rows, spot:, window: 250)
    rows = window_rows(rows, spot: spot, width: window)

    grouped = group_by_strike(rows)

    # OI-weighted delta and gamma per strike
    aggregated = grouped.transform_values do |strike_rows|
      {
        delta: strike_rows.sum { |r| r[:delta] * r[:open_interest] },
        gamma: strike_rows.sum { |r| r[:gamma] * r[:open_interest] }
      }
    end

    strikes = aggregated.keys
    velocity = {}

    strikes.each_with_index do |strike, i|
      next if i == 0 || i == strikes.length - 1

      k_prev = strikes[i - 1]
      k_next = strikes[i + 1]

      d_prev = aggregated[k_prev][:delta]
      d_next = aggregated[k_next][:delta]

      delta_slope = (d_next - d_prev) / (k_next - k_prev)
      gamma       = aggregated[strike][:gamma]

      # Magnitude only — speed, not direction
      velocity[strike] = delta_slope.abs * gamma
    end

    velocity
  end
end