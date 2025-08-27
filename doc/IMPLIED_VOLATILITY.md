# Implied Volatility

## What is Implied Volatility?

**Implied volatility** is the value of volatility consistent with observed market prices under the Black-Scholes model. Unlike historical volatility (which can be calculated from past price movements), implied volatility is derived from current option market prices and represents the market's expectation of future volatility.

## Key Concept

The Black-Scholes model assumes that you can characterize the movement patterns of an asset's price in terms of the volatility and drift alone. However, when you use historical volatility in Black-Scholes pricing formulas, the predicted price will (usually) fall below observed market prices.

This happens because Black-Scholes, by virtue of characterizing assets by volatility alone, underestimates risk in the underlying asset, and therefore underestimates risk in the derivative asset as well.

## Calculation Method

### Inverse Problem Approach

The binomial options pricing model actually predicts the option premium given the volatility, not the other way around. However, since we are interested in computing implied volatility from option premium, we invert the model.

### Root-Finding Algorithm

This can be done by using a root-finding algorithm – while Newton's method is a typical choice, it requires us to compute the derivative of the function of interest. Instead we chose Brent's method, an algorithm that combines characteristics of the secant and bisection algorithms.

### Input Price Considerations

Implied volatility calculations are often done using the midpoint between the bid and ask for an option contract. This is because the options market has quite a low volume of trades (around 300/sec at the time of this post). However, the most recent quote will have been within the last day, making bid-ask midpoint more current than last trade price.

## Required Inputs for Calculation

The binomial options pricing model requires six inputs:

1. **Time to maturity**
2. **Spot price** (current underlying price)
3. **Strike price**
4. **Volatility** (this is what we're solving for)
5. **Dividend yield**
6. **Risk-free interest rate**

### Dividend Yield Calculation
We use historical dividend payouts over the past year to estimate annualized yield. Another method is to simply use the most recent dividend and multiply by the frequency.

### Risk-Free Rate
Typically treasury bond yields are used to estimate the risk-free interest rate -- however, options traders prefer to use something called SOFR, the Secured Overnight Financing Rate.

## Implied Volatility Surface

While volatility can be said to be a property of the underlying asset, implied volatility depends on the parameters of the option contract, particularly the expiration date and the strike price. This gives rise to an implied volatility surface, where implied volatility varies with respect to time to maturity and strike price.

## Implementation Challenges

**For in-the-money options:** the premium should never fall below the intrinsic (exercise) value, otherwise this would represent an arbitrage opportunity.

For in-the-money options, we observed a significant portion of contracts with bids that were below the intrinsic value, which can cause the midpoint calculation to be invalid for pricing models.

## Algorithm Pseudocode

```
FUNCTION CalculateImpliedVolatility(marketPrice, S0, K, T, r, dividendYield)
    // Parameters:
    // marketPrice = observed option market price (bid-ask midpoint)
    // S0 = current stock price
    // K = strike price
    // T = time to expiration (in years)
    // r = risk-free rate
    // dividendYield = annualized dividend yield

    // Define objective function
    FUNCTION ObjectiveFunction(volatility)
        theoreticalPrice = BinomialOptionPrice(S0, K, T, r, volatility, dividendYield, n)
        RETURN theoreticalPrice - marketPrice
    END FUNCTION

    // Set bounds for volatility search
    volLow = 0.001   // 0.1%
    volHigh = 5.0    // 500%

    // Ensure opposite signs at bounds
    IF sign(ObjectiveFunction(volLow)) == sign(ObjectiveFunction(volHigh)) THEN
        RETURN "No solution found - check inputs"
    END IF

    // Use Brent's method to find root
    impliedVol = BrentsMethod(ObjectiveFunction, volLow, volHigh, tolerance=1e-6)

    RETURN impliedVol
END FUNCTION
```

*Reference: [Polygon.io - Greeks and Implied Volatility](https://polygon.io/blog/greeks-and-implied-volatility)*