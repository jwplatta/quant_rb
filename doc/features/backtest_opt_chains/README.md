# Backtest with Option Chains

We want to be able to backtest against sensible and realistic option chains. This is tricky because option chain data is hard to access and it's important to have point in time option chain data which means samples of the same option chain over time. We will need to support at least 3 methods for working with option chain data:
- We want to be able to generate a completely synthetic option chain from the underlying prices and some proxy for implied volatility
- We want to be able to work with the Massive option chain samples that only provide open, close, high low values and we need to infer the implied volaility and the greeks
- We want to be able to work with the schwab option chain samples which are high quality and include all values: prices, greeks, implied vol

## Constraints

- All the option chains used in the backtests need to be arbitrage free. So there should be monotonic pricing. We will need some sort of validation on this and a method of correcting any inconsistencies in the pricing of the options.
- we will need to use the tickrake gem to load data. `Tickrake::DataLoader` see https://github.com/jwplatta/tickrake and the source code is on this computer at ~/repos/tickrake. We will also have to add this gem as a dependency directly from it's github repo because I havent' released it yet.

## Synethic Option Chains

I believe the synthetic option chains are already implemented. But let's check and verify their logic:
- To generate synthetic option chains we will need to get the underlying prices (we're primarly concerned with SPX options so we'll use that as an example). For example, get the SPX min by min prices
- Then we need a measure of the implied volatility. For the SPX options we can use VIX/VIX9D/VIX1D.
- So I think the interface for the qaunt_rb's synethic option chain generator needs to accept prices for the underlying and then some measure of the implied volatility. We'll need to validate that they have the same frequency and the same number of samples. If they don't raise an informative error.
  - For the IV proxy we probably want to allow for multiple based on the option's days to expiration. For example with SPX options we want to use the VIX for options that are 10DTE or more, for options that are 1DTE to 9DTE we want to use the VIX9D and for options that are 0DTE we want to use VIX1D. So the quant_rb interface should all the client to pass multiple proxies for IV based on days to expiration. And if the client only passes 1 proxy, then teh default behavior should be to just use that one proxy for all option chains.
- So with IV and the underyling prices, we will then use one of the pricing models to calculate the price:
  - Black Scholes (again think this is already implemented)
  - Binomial pricing model
- We can then back out the greeks as well.
- We need to come up with a way to simulate the mark, bid, ask price

## Loading Sampled Options

- There are two sources of sampled option chains located on this computer in:
  - ~/.tickrake/data/options/massive
    - These samples are min by min but incomplete and we will need to interpolate some of the information
    - This folder has ~4 million samples (files) in it. So be careful reading from it. The samples themselves are pretty small files.
  - ~/.tickrake/data/options/schwab
- So I think we can make some assumptions about the structure of the data. I think those assumptions should like in data objects defined here in the quant_rb gem. At some point I think we extract like a quant_core module. Let's assume that when we read the data from the source files that it will fit into the structure defined in the quant_rb. I don't want to maintain any mappings right now that would add unnecessary complexity overhead.
- We'll need to implement some sort of general option chain loading functionality for the backtests. I think this might already be implemented in the initial implementation of the quant_rb backtest engine. double check please.

### Search for Sample Option Chains on this Computer using Tickrake

Use the `tickrake` utility CLI for finding option chains on this machine rather than searching through the folders directly. You can get the file path to load.
```sh
$ tickrake help
$ tickrake query --type options --provider massive --ticker SPXW --limit 10 --format json
$ tickrake query --type options --provider massive --ticker SPXW  --start-date 2024-10-01 --end-date 2024-10-31 --format json
$ tickrake query --type options --provider schwab --ticker SPXW --limit 10 --format json
$ tickrake query --type options --provider massive --ticker SPXW --limit 10 --format json
```

## Sampled Option Chains from Schwab

- The sampled option chains from schwab will have all the relevant chain data - prives, IV, greeks
- All we need to do is run the validators to make sure the data is arbitrage free. If it isn't, then we need to fix it.

## Sampled Option Chains from Massive

- The Massive option chain samples do not provide the complete set of strikes for the option chain. So we will need to interpolate the options that are not in the sample.
- The Massive option chain samples do not have the mark, bid, ask prices. Instead they have the the open, close, high low. So we will need to come up with a sensible strategy for estimately the mark, bid and ask. Maybe just the OCHL average?
- For some examples see some of the option chains from Massive in the ~/.tickrake/data/options/massive directory. Be careful though because this directory has a lot of files. There are over ~4 million samples in this folder.
- I'm not sure if we want to try to back out the IV from the price in order to calculate the greeks or whether we want to follow the same strategy as the synthetic option chains and use the underyling prices and some sort of proxy of the IV. My hunch is that the option chain will be more coherent if we back out the IV from the prices, but we will need to be careful about applying the validations to ensures the option chain is arbitrage free.
- Massive's option chains are compacted through time, e.g. suppose we have an option chain sample at t_0 and there are not changes from t_0 to t_2, then generally Massive will not include a t_1 option chain sample. I'm not sure how to handle this, maybe the backtest engine should just fast forward to the next available sample. Maybe we should try to simulate an option chain sample at t_1. I think the first approach is easier right now. So maybe start with that.
- I think in general, we just want to fast forward to the next available option chain sample if we are missing samples, e.g. if we're running a backtest on minute frequency and at we have a sample at minute 1, but the next sample it 5 minutes later, then just skip to that next sample. It won't be a perfect backtest but it'll be good enough.

## Calculating Greeks for Option Chains

For the purely synthetic option chains. We will need to back out the greeks from a pricing model:
- Black Scholes
- Cox-Ross-Rubinstein (CRR) binomial option pricing model

Let's implement both these methods and pass the name of which pricing model to use to the code that need to generate the greeks for hte option chain.

So we should implement these somewhere sensible that doesn't clutter the codebase with equations. So we will need use something similar to stuff like:
- Use Newton–Raphson (fast, needs Vega)
- Or bisection (slower but robust)
- Libraries do this internally (e.g. QuantLib, scipy)

Let's either implement a simple version of like bisection search. Or if there's a well established and reliable ruby gem out there that we can use, let's use that (I think there's like scikit learn like gem that we should check.)