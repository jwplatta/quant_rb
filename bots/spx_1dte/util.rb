def round_up_to_nearest(value, increment)
  ((value / increment).ceil * increment).round(2)
end

def round_down_to_nearest(value, increment)
  ((value / increment).floor * increment).round(2)
end
