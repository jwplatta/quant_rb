# Simple Portfolio Growth Calculator
import matplotlib.pyplot as plt
import numpy as np

def calculate_portfolio_growth(initial_amount, weekly_rate, expenses, years):
    weeks = years * 52

    portfolio_values = []
    current_value = initial_amount

    for week in range(weeks + 1):
        portfolio_values.append(current_value)
        if week < weeks:
            net_weekly_rate = weekly_rate - expenses
            weekly_gain = current_value * net_weekly_rate
            current_value += weekly_gain

    final_amount = current_value
    total_return = (final_amount / initial_amount - 1) * 100
    annual_return = ((final_amount / initial_amount) ** (1/years) - 1) * 100

    return final_amount, total_return, annual_return, portfolio_values

initial = 100_000      # $100k starting
weekly_rate = 0.018    # 1% per week gross return
expenses = 0.004     # 0.2% per week in expenses (fees, taxes, etc.)
years = 10            # 10 years

final, total_ret, annual_ret, values = calculate_portfolio_growth(initial, weekly_rate, expenses, years)

net_weekly_rate = weekly_rate - expenses
print(f"Starting amount: ${initial:,}")
print(f"Gross weekly return: {weekly_rate:.1%}")
print(f"Weekly expenses: {expenses:.1%}")
print(f"Net weekly return: {net_weekly_rate:.1%}")
print(f"Time period: {years} years ({years * 52} weeks)")
print(f"Final amount: ${final:,.0f}")
print(f"Total return: {total_ret:.1f}%")
print(f"Annual return: {annual_ret:.1f}%")

manual_check = initial
for week in range(520):
    weekly_gain = manual_check * net_weekly_rate
    manual_check += weekly_gain
print(f"\nManual check (week-by-week): ${manual_check:,.0f}")

weeks_array = np.arange(0, len(values))
years_array = weeks_array / 52

plt.figure(figsize=(10, 6))
plt.plot(years_array, values, 'b-', linewidth=2)
plt.title(f'Portfolio Growth Over 10 Years ({net_weekly_rate:.1%} Net Weekly Return)', fontsize=14, fontweight='bold')
plt.xlabel('Years')
plt.ylabel('Portfolio Value ($)')
plt.grid(True, alpha=0.3)
plt.gca().yaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'${x:,.0f}'))
plt.tight_layout()
plt.show()