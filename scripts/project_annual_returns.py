import matplotlib.pyplot as plt
import numpy as np

def project_portfolio(initial_value, monthly_yield, monthly_expenses, years=30):
    """
    Project portfolio growth over time

    Parameters:
    initial_value (float): Starting portfolio value
    monthly_yield (float): Monthly return rate (e.g., 0.007 for 0.7% monthly)
    monthly_expenses (float): Monthly expenses in dollars
    years (int): Number of years to project

    Returns:
    months (array): Array of months
    values (array): Array of portfolio values
    """
    months = np.arange(0, years * 12 + 1)
    values = np.zeros(len(months))
    values[0] = initial_value

    for i in range(1, len(months)):

        rand_monthly_yield = np.random.choice([0.01, 0.02, 0.03, 0.04, 0.05, 0.06]).item()
        values[i] = values[i-1] * (1 + rand_monthly_yield) - monthly_expenses
        values[i] = max(0, values[i])

    return months, values

def plot_portfolio_projection(initial_value, monthly_yield_pct, annual_expenses, n_years):
    """
    Create portfolio projection plot

    Parameters:
    initial_value (float): Starting portfolio value
    monthly_yield_pct (float): Monthly yield percentage (e.g., 0.7 for 0.7%)
    annual_expenses (float): Annual expenses in dollars
    """
    monthly_yield = monthly_yield_pct / 100
    monthly_expenses = annual_expenses / 12

    # Project for 30 years
    months, values = project_portfolio(initial_value, monthly_yield, monthly_expenses, n_years)
    print(values)


    years = months / 12

    # Create the plot
    plt.figure(figsize=(12, 8))
    plt.plot(years, values, linewidth=2, color='navy', label='Portfolio Value')

    # Add reference line for no growth scenario
    no_growth = [initial_value - (monthly_expenses * month) for month in months]
    no_growth = [max(0, val) for val in no_growth]  # Don't go negative
    plt.plot(years, no_growth, '--', color='red', alpha=0.7, label='No Growth (Expenses Only)')

    plt.title(f'Portfolio Projection\nInitial: \\${initial_value:,.0f} | Monthly Yield: {monthly_yield_pct}% | Annual Expenses: \\${annual_expenses:,.0f}',
              fontsize=14, fontweight='bold')
    plt.xlabel('Years', fontsize=12)
    plt.ylabel('Portfolio Value ($)', fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.legend()

    # Format y-axis as currency
    plt.gca().yaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'\\${x:,.0f}'))

    # Add some key statistics as text
    final_value = values[-1].item()  # Convert numpy array element to scalar
    total_return = final_value - initial_value
    total_expenses_paid = annual_expenses * n_years

    print(type(final_value))
    print(f"{final_value:,.0f}")

    print(type(total_expenses_paid))

    stats_text = f"Final Value: {final_value:,.0f}"
    stats_text += f"\nTotal Growth: {total_return:,.0f}"
    stats_text += f"\nTotal Expenses: {total_expenses_paid:,.0f}"
    print(stats_text)



    plt.text(0.02, 0.98, stats_text, transform=plt.gca().transAxes,
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))

    plt.tight_layout()
    plt.show()

    return final_value

# Example usage
if __name__ == "__main__":
    # Example parameters
    initial_portfolio = 400000  # $100k starting portfolio
    monthly_yield = 3.0        # 0.7% monthly return (about 8.7% annual)
    annual_expenses = 2000     # $1000 per year in expenses
    years = 10

    print("Projecting portfolio growth...")
    print(f"Initial Value: ${initial_portfolio:,}")
    print(f"Monthly Yield: {monthly_yield}%")
    print(f"Annual Expenses: ${annual_expenses}")
    print()

    final_value = plot_portfolio_projection(initial_portfolio, monthly_yield, annual_expenses, years)
    print(f"Final projected value after 30 years: ${final_value:,.0f}")