import matplotlib.pyplot as plt
import numpy as np

strikes = [6200, 6205, 6210, 6215, 6220, 6225, 6230, 6235, 6240, 6245, 6250, 6255, 6260, 6265, 6270, 6275, 6280, 6285, 6290, 6295, 6300, 6305, 6310, 6315, 6320, 6325, 6330, 6335, 6340, 6345, 6350, 6355, 6360, 6365, 6370, 6375, 6380, 6385, 6390, 6395, 6400, 6405, 6410, 6415, 6420, 6425, 6430, 6435, 6440, 6445, 6450]

call_oi = [315, 97, 62, 55, 165, 72, 39, 66, 50, 71, 132, 75, 432, 216, 425, 2025, 555, 177, 441, 207, 660, 337, 1484, 498, 552, 1055, 2164, 1658, 1526, 1247, 3139, 2608, 2623, 1556, 2235, 2810, 2914, 3684, 2971, 3071, 5974, 3050, 3985, 8859, 5345, 12784, 1760, 860, 1204, 788, 2018]

put_oi = [2842, 532, 1519, 8064, 1459, 2530, 1183, 1226, 1652, 973, 2277, 1397, 1652, 1630, 1127, 1925, 1724, 1005, 1679, 2013, 5116, 2025, 1431, 2052, 1523, 2873, 1918, 1010, 1773, 1216, 2150, 1232, 1077, 652, 607, 503, 144, 52, 37, 23, 100, 15, 24, 12, 15, 12, 11, 0, 4, 12, 24]

# Create the plot
plt.figure(figsize=(14, 8))

# Plot both lines
plt.plot(strikes, call_oi, 'b-', linewidth=2, label='Call Open Interest', marker='o', markersize=4)
plt.plot(strikes, put_oi, 'r-', linewidth=2, label='Put Open Interest', marker='s', markersize=4)

# Customize the plot
plt.title('SPX Option Open Interest by Strike (Expiration: July 24, 2025)', fontsize=16, fontweight='bold')
plt.xlabel('Strike Price', fontsize=12)
plt.ylabel('Open Interest', fontsize=12)
plt.grid(True, alpha=0.3)
plt.legend(fontsize=12)

# Add vertical line at current SPX price
current_spx = 6376.84
plt.axvline(x=current_spx, color='green', linestyle='--', alpha=0.7, linewidth=2, label=f'Current SPX: ${current_spx}')
plt.legend(fontsize=12)

# Format x-axis to show strike prices clearly
plt.xticks(strikes[::5], rotation=45)  # Show every 5th strike price
plt.tight_layout()

# Add annotations for highest open interest points
max_call_idx = call_oi.index(max(call_oi))
max_put_idx = put_oi.index(max(put_oi))

plt.annotate(f'Max Call OI: {max(call_oi):,}\nStrike: {strikes[max_call_idx]}',
             xy=(strikes[max_call_idx], call_oi[max_call_idx]),
             xytext=(strikes[max_call_idx] + 10, call_oi[max_call_idx] + 1000),
             arrowprops=dict(arrowstyle='->', color='blue', alpha=0.7),
             fontsize=10, color='blue')

plt.annotate(f'Max Put OI: {max(put_oi):,}\nStrike: {strikes[max_put_idx]}',
             xy=(strikes[max_put_idx], put_oi[max_put_idx]),
             xytext=(strikes[max_put_idx] - 30, put_oi[max_put_idx] + 1000),
             arrowprops=dict(arrowstyle='->', color='red', alpha=0.7),
             fontsize=10, color='red')

plt.show()

# Print some summary statistics
print("SPX Option Chain Summary:")
print(f"Current SPX Price: ${current_spx}")
print(f"Total Call Open Interest: {sum(call_oi):,}")
print(f"Total Put Open Interest: {sum(put_oi):,}")
print(f"Highest Call OI: {max(call_oi):,} at strike {strikes[max_call_idx]}")
print(f"Highest Put OI: {max(put_oi):,} at strike {strikes[max_put_idx]}")
print(f"Put/Call Ratio (by OI): {sum(put_oi)/sum(call_oi):.2f}")