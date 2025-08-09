import json
import matplotlib.pyplot as plt

# Load option chain data
with open('../tmp/SPX-8-11-to-8-12.json', 'r') as f:
    data = json.load(f)

# Get $SPX volatility
spx_vol = data.get('volatility')

# Helper to extract volatilities for a given expDateMap
def extract_vols(exp_date_map):
    strikes = []
    vols = []
    for exp, strike_dict in exp_date_map.items():
        for strike, options in strike_dict.items():
            # Some strikes may have empty lists
            if options and isinstance(options, list):
                opt = options[0]
                strikes.append(float(strike))
                vols.append(opt.get('volatility'))
    return strikes, vols

# Extract call and put volatilities
call_exp_map = data['callExpDateMap'].get('2025-08-11:3', {})
put_exp_map = data['putExpDateMap'].get('2025-08-11:3', {})
call_strikes, call_vols = extract_vols({'2025-08-11:3': call_exp_map})
put_strikes, put_vols = extract_vols({'2025-08-11:3': put_exp_map})

# Plot
plt.figure(figsize=(10,6))
plt.plot(call_vols, call_strikes, label='Call Volatility', color='blue')
plt.plot(put_vols, put_strikes, label='Put Volatility', color='red')
plt.axvline(spx_vol, color='green', linestyle='--', label='$SPX Volatility')
plt.xlabel('Volatility')
plt.ylabel('Strike Price')
plt.title('SPX Option Chain Volatility')
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.show()
