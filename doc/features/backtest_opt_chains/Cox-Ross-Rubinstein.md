Here's pseudocode for the Cox-Ross-Rubinstein (CRR) binomial option pricing model:

```
FUNCTION CRR_OptionPrice(S0, K, T, r, sigma, n, optionType)
    // Parameters:
    // S0 = current stock price
    // K = strike price
    // T = time to expiration
    // r = risk-free rate
    // sigma = volatility
    // n = number of time steps
    // optionType = "call" or "put"

    // Calculate CRR parameters
    dt = T / n                           // time step
    u = exp(sigma * sqrt(dt))           // up factor
    d = 1 / u                           // down factor
    p = (exp(r * dt) - d) / (u - d)     // risk-neutral probability
    discount = exp(-r * dt)             // discount factor

    // Initialize asset price tree
    CREATE array S[n+1][n+1]

    // Build forward asset price tree
    FOR i = 0 TO n
        FOR j = 0 TO i
            S[i][j] = S0 * u^j * d^(i-j)
        END FOR
    END FOR

    // Initialize option value array
    CREATE array V[n+1][n+1]

    // Calculate terminal option values (at expiration)
    FOR j = 0 TO n
        IF optionType == "call" THEN
            V[n][j] = max(0, S[n][j] - K)
        ELSE IF optionType == "put" THEN
            V[n][j] = max(0, K - S[n][j])
        END IF
    END FOR

    // Backward induction to find option price
    FOR i = n-1 DOWN TO 0
        FOR j = 0 TO i
            // Expected option value
            expectedValue = p * V[i+1][j+1] + (1-p) * V[i+1][j]
            V[i][j] = discount * expectedValue

            // For American options, check early exercise
            IF isAmerican THEN
                IF optionType == "call" THEN
                    intrinsicValue = max(0, S[i][j] - K)
                ELSE IF optionType == "put" THEN
                    intrinsicValue = max(0, K - S[i][j])
                END IF
                V[i][j] = max(V[i][j], intrinsicValue)
            END IF
        END FOR
    END FOR

    RETURN V[0][0]  // Option price at t=0
END FUNCTION

// Example usage:
// callPrice = CRR_OptionPrice(100, 105, 0.25, 0.05, 0.2, 50, "call")
// putPrice = CRR_OptionPrice(100, 105, 0.25, 0.05, 0.2, 50, "put")
```

## Key Features

**CRR Parameters**: Uses the specific formulation where `u = exp(σ√Δt)` and `d = 1/u`
**Risk-neutral probability**: `p = (e^(rΔt) - d)/(u - d)`
**Forward tree building**: Constructs the complete asset price tree first
**Backward induction**: Works from expiration back to present to find option value
**American option handling**: Includes early exercise check (optional)
**Flexibility**: Handles both calls and puts

The algorithm has O(n²) time and space complexity, making it efficient for reasonable values of n (typically 50-500 steps).

## Important Note: Time Step Units

The time step `dt` in the Cox-Ross-Rubinstein model should be expressed in **years** (as a fraction of a year).

This is because:

1. **Time to expiration (T)** is typically expressed in years
2. **Risk-free rate (r)** is typically an annual rate
3. **Volatility (σ)** is typically annualized volatility

So when you calculate `dt = T / n`:
- If T = 0.25 (3 months) and n = 50 steps, then dt = 0.005 years per step
- If T = 1.0 (1 year) and n = 252 steps, then dt ≈ 0.004 years per step (about 1 trading day)

**Common time step examples:**
- Daily steps: dt = 1/252 ≈ 0.004 years (252 trading days per year)
- Weekly steps: dt = 1/52 ≈ 0.019 years
- Monthly steps: dt = 1/12 ≈ 0.083 years

The key is maintaining **dimensional consistency** - since r and σ are annualized, dt must also be in years so that:
- `r * dt` is dimensionless
- `σ * sqrt(dt)` is dimensionless
