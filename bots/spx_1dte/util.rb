def round_up_to_nearest(value, increment)
  ((value / increment).ceil * increment).round(2)
end

def round_down_to_nearest(value, increment)
  ((value / increment).floor * increment).round(2)
end

def next_business_day
  tomorrow = Date.today + 1
  case tomorrow.wday
  when 0 # Sunday
    tomorrow + 1
  when 6 # Saturday
    tomorrow + 2
  else
    tomorrow
  end
end

# def find_spread_by_delta(target_delta, spread_width, contract_type)
#   opts = if contract_type == 'CALL'
#             options_chain.call_opts
#           else
#             options_chain.put_opts
#           end

#   best_opt = opts.select { |o| o.delta }.min_by { |o| (o.delta.abs.to_f - target_delta.to_f).abs }
#   raise StandardError, "Cannot find option with target delta" unless best_opt

#   short_leg = new_option_leg(best_opt.symbol, best_opt.strike, best_opt.mark, best_opt.delta, contract_type, best_opt.expiration_date)
#   short_strike = best_opt.strike

#   long_leg = if contract_type == 'CALL'
#     opts.find { |opt| opt.strike == short_strike + spread_width }.then do |opt|
#       new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
#     end
#   else
#     opts.find { |opt| opt.strike == short_strike - spread_width }.then do |opt|
#       new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
#     end
#   end

#   VerticalSpread.new(short_leg, long_leg, contract_type)
# end
