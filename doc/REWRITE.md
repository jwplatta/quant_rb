# Rewrite

I want to do a complete refactor of the options_trader gem. The goal is to be able to quickly support running some backtests on short vol carry strategies on the SPX.

## Context
The most recently used code here in the @bots/ directory and the original project was all housed in the /lib folder. The original project depended on the schwab_rb gem, this new project will still need to be able to work with both the schwab_rb gem (version 0.9.2) and it will also need to work with `ib-api` gem for working with interactive brokers.

The immediate goal right now is to support backtests, but we will eventually want to take a strategy that we've backtested and be able to deploy it using the same code, i.e. the implemented strategy should work for backtesting, paper trading, and live trading. We will likely be using interactive brokers to paper trade and live trade, but we should still support schwab as well.

## Inspiration
- QuantConnect python api. In particular I like how it uses hooks inside the implemented trading algo to handle events and new market data.
  - For example the `self.schedule.on` in the example python quant connect algo in the @ddoc/spxw_7dte_recenter/main.py. That method is provided by the quant connect sdk, then other things like hte IronCondorEntryOrderManager.py are developed by me on the basis of hte quant connect sdk. We want the optinios_trader gem to work the same way.
- Review the keys concepts of quant connects algorithm engine here: https://www.quantconnect.com/docs/v2/writing-algorithms/key-concepts/algorithm-engine
  - We want to add the bare minimum numbers of concepts to get options_trader gem working for backtests.
  - for example, I think we want to support htese events handlers:
  ```python
   # Other Event Handlers
    def on_data(self, slice: Slice) -> None:
    def on_end_of_day(self, symbol: Symbol) -> None:
    def on_end_of_algorithm(self) -> None:
  ```
  - And we want to support some number of indicator helps or make it easy to define them:
  ```python
  # Indicator Helpers
    def sma(self, symbol: Symbol, period: int) -> SimpleMovingAverage:
  ```
  - however we don't need to support the large datasets modules that quant connect does. We will only need to do something very minimal because I have another gem `tickrake` that uses my `schwab_rb` to scrape candles and option chain samples regularly and stores them in the ~/.tickrake/data folder on the local machine. We will just need to be able to load these csv files in order to run the backtests.
  - We will also name things "strategies" instead of "algorithms" as quant connect does
  -
- After we get the gem setup initially, we will work on producing a synthetic option chain from spx and vix, vix1d, vix9d minute bars. A prototype is in the @doc/generate_option_chain.rb file. This will allow us to backtest option strategies locally

## Notes

- Nothing needs to backwards compatible here
- I think we can delete anything that was scraping data because this is all handled by the tickrake gem now
- Leave the implement bot in the /bots folder alone. Don't make any changes here, but you can refer to it. We want to change the code in the actual lib of the gem.
- I think we can get rid of the charts module, that's unncessary now
- The latest of the schwab_rb gem is located on this machine at ~/repos/schwab_rb. Refer to it as you need
- Example data for testing can be found in the ~/.tickrake/data folder. Some of these files are large, so explore them incrementally, check out the first few lines before loading the whole file to see if it has what you need
- More example of quant connect algos can be found in ~/repos/trade_lab/qc. Explore this as you need.
- Please refer to the quant connect documentation as need starting with this page: https://www.quantconnect.com/docs/v2/writing-algorithms/key-concepts/algorithm-engine
- Documentation for the ib-api gem can be found here: https://ib-ruby.github.io/ib-doc/

## Feedback

- As I'm looking at the new structure of the gem it's becoming clear to me that it doesn't really make sense to just focus on options strategies. It the gem should be general for all algo strategies (on stocks, etfs, indexes, futures, options, etc.). So we'll also need to rename the gem to something clearer.
  - For starters though, we are focusing on being able to backtest these short vol carry with options strategies
- I specifically said to rename the `algorithm_base` to `strategy_base` in the engine module
  - so instead of `OptionsTrader::Algorithm` we want `OptionsTrader::Strategy`
- These modules make sense: engine, data, data_objects, bokers, reporting
  - One caveat, I don't want to refer to tickrake directly in the options_trader gem. Tickrake is just a job scheduler for scrapping data from the brokers. options_trader does not need to depend on it. We just need to be able to configure options_trader to point to the source of the backtesting data
  - Still we will probably have to have some of the filename logic int he options_trader gem or else it just won't be able to successfully load the csv files.
- I don't think we need these modules: strategies and search
  - So we can get rid of Phase 2: Search Layer Cleanup
  - So the logic in these modules should be implemented in a project that consumes the options_trader gem. Maybe in the future we'll provide some basic implementations of strategies out of the box. But for right now. We don't need to do this.
  - However, let's just move this code to the doc folder so we can still use it as reference
- Then we want to be able to work on some of these refactors independently and at the same time. Can we structure hte project so that, for example, one agent can work on teh data layer while another works on the engine core