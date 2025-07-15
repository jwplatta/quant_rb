# Options Trader

## Resources

- [schwab-py](https://schwab-py.readthedocs.io/en/latest/getting-started.html)
Procore's CIK:
- https://data.sec.gov/submissions/CIK0001106321.json
CIK0001106321

## Example DSL

Implement a trade index that follows these requirements:
- it has a method to register a trade that takes a trade ID and then appends it to a csv file with following columns:
  - trade_id
  - state: OPEN | CLOSED
  - created_at
  - updated_at
- if the trade index class can't find the index file, then it should raise and prompt the user to create it.
-

Help me plan implementing the #bot.rb class that manages the a #trade.rb object. Here are some requirements. what other things should I consider? What are the steps we should follow to implement this?
- This bot should repeatedly call the `#next` method on the trade until the trade is exited.
- When the trde is first entered, the bot should write the trade.trade_id to a file named CURRENT_#{bot.name}_TRADE.txt in the same directory as the running bot.
- when the trade is exited the bot should clear the file or simply write over it with a new trade id.
- The bot needs to be able to configure the trade, start the trade process and them monitor the trade until it is exited and be able to put on a new trade.
- Ultiamtely we want to also implement a DSL like below that will allow us to configure the bot and trade in a more readable way.

```ruby
bot = Platypi.create_bot do
  set_name 'SPX Weekly Iron Condor Bot'
  set_mode :paper # :simulation | :live

  set_account '123123123'

  # NOTE: optional setting, default to :immediately
  # enter_trade_when :immediately
  # enter_trade_when :after, '2pm'
  # enter_trade_when :before, '12:00pm'

  use_strategy 'ironcondor' do
    set_underlying_symbol '$SPX'
    set_option_root 'SPXW'
    set_settlement_type 'P'
    set_days_to_expiration 1
    set_min_credt 1.00
    set_min_open_interest 25
    set_max_delta 0.15
  end

  exit_when do
    max_loss_threshold 2.5 # 2x the credit received
    profit_target_threshold 0.7 # 70% of the credit received
  end

  # NOTE: optional, ignore for now
  adjust_strategy_when do
    set_max_delta 0.22
    set_max_loss 2.0

    do_rollup_when do
      delta_below 0.3
    end
    do_rollout_when do
      delta_above 0.40
    end
  end

  alert_when do
  end
end

bot.start
```