class DeltaSmoother
  def initialize(empirical_deltas: [])
    # empirical_deltas should be array of hashes with :moneyness, :delta, :weight
    @data = empirical_deltas.sort_by { |point| point[:moneyness] }
  end

  # Simple moving average of K nearest neighbors
  def smooth_delta_knn(target_moneyness, k: 5)
    # Find K closest points by moneyness
    distances = @data.map do |point|
      {
        point: point,
        distance: (point[:moneyness] - target_moneyness).abs
      }
    end

    nearest = distances.sort_by { |d| d[:distance] }.first(k)

    # Simple average
    total_delta = nearest.sum { |n| n[:point][:delta] }
    total_delta / nearest.length.to_f
  end

  # Weighted by distance (closer points matter more)
  def smooth_delta_weighted(target_moneyness, bandwidth = 0.05)
    weights = []
    deltas = []

    @data.each do |point|
      distance = (point[:moneyness] - target_moneyness).abs

      # Skip points too far away
      next if distance > bandwidth * 3

      # Gaussian weight (closer = higher weight)
      weight = Math.exp(-(distance / bandwidth) ** 2)

      # Also weight by data quality if available
      weight *= point[:weight] if point[:weight]

      weights << weight
      deltas << point[:delta]
    end

    return nil if weights.empty?

    # Weighted average
    weighted_sum = deltas.zip(weights).sum { |delta, weight| delta * weight }
    total_weight = weights.sum

    weighted_sum / total_weight
  end

  # Moving average within a window
  def smooth_delta_window(target_moneyness, window_size = 0.1)
    # Find all points within the window
    nearby_points = @data.select do |point|
      (point[:moneyness] - target_moneyness).abs <= window_size / 2.0
    end

    return nil if nearby_points.empty?

    # Quality-weighted average
    if nearby_points.first[:weight]
      total_weighted = nearby_points.sum { |p| p[:delta] * p[:weight] }
      total_weights = nearby_points.sum { |p| p[:weight] }
      total_weighted / total_weights
    else
      # Simple average
      nearby_points.sum { |p| p[:delta] } / nearby_points.length.to_f
    end
  end

  # Smooth entire surface (for all your target strikes)
  def smooth_surface(target_moneyness_values, method = :weighted)
    target_moneyness_values.map do |moneyness|
      case method
      when :knn
        smooth_delta_knn(moneyness)
      when :weighted
        smooth_delta_weighted(moneyness)
      when :window
        smooth_delta_window(moneyness)
      end
    end
  end
end

# Usage:
# empirical_data = [
#   { moneyness: 0.95, delta: -0.45, weight: 1.0 },
#   { moneyness: 0.98, delta: -0.25, weight: 0.8 },
#   { moneyness: 1.02, delta: 0.25, weight: 1.0 },
#   { moneyness: 1.05, delta: 0.45, weight: 0.9 }
# ]
#
# smoother = DeltaSmoother.new(empirical_data)
#
# # Get smoothed delta for target strike
# target_moneyness = 1.01  # Your target option
# smoothed_delta = smoother.smooth_delta_weighted(target_moneyness)
#
# puts "Smoothed delta: #{smoothed_delta}"