require 'matrix'

class PolynomialRegression
  attr_reader :coefficients

  def initialize(degree: 2)
    @degree = degree
    @coefficients = nil
  end

  def fit(x_values, y_values)
    raise "x and y must have same length" unless x_values.length == y_values.length

    # Create design matrix (Vandermonde matrix)
    # For degree 3: [1, x, x^2, x^3] for each x value
    matrix_data = x_values.map do |x|
      (0..@degree).map { |power| x ** power }
    end

    design_matrix = Matrix.rows(matrix_data)
    y_vector = Matrix.column_vector(y_values)

    # Solve normal equation: (X^T * X) * coeffs = X^T * y
    xt_x = design_matrix.transpose * design_matrix
    xt_y = design_matrix.transpose * y_vector

    @coefficients = xt_x.inverse * xt_y

    self
  end

  def predict(x)
    raise "Must fit model first" unless @coefficients

    # Calculate: a0 + a1*x + a2*x^2 + ... + an*x^n
    result = 0
    (0..@degree).each do |power|
      result += @coefficients[power, 0] * (x ** power)
    end

    result
  end

  def predict_batch(x_values)
    x_values.map { |x| predict(x) }
  end
end

# Usage example:
# x_data = [0.8, 0.9, 1.0, 1.1, 1.2]  # moneyness values
# y_data = [-0.8, -0.3, 0.0, 0.3, 0.7]  # delta values
#
# model = PolynomialRegression.new(3)  # cubic polynomial
# model.fit(x_data, y_data)
#
# # Predict delta for new moneyness
# predicted_delta = model.predict(1.05)
# puts "Predicted delta: #{predicted_delta}"