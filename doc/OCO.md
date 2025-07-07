# Conditional Order: One Cancels Another

Sell 2 shares of XYZ at a Limit price of $45.97 and Sell 2 shares of XYZ with a Stop Limit order where the stop price is $37.03 and limit is $37.00. Both orders are sent at the same time. If one order fills, the other order is immediately cancelled. Both orders are good for the Day. Also known as an OCO order.


```json
{
  "orderStrategyType": "OCO",
  "childOrderStrategies": [
   {
    "orderType": "LIMIT",
    "session": "NORMAL",
    "price": "45.97",
    "duration": "DAY",
    "orderStrategyType": "SINGLE",
    "orderLegCollection": [
     {
      "instruction": "SELL",
      "quantity": 2,
      "instrument": {
       "symbol": "XYZ",
       "assetType": "EQUITY"
      }
     }
    ]
   },
   {
    "orderType": "STOP_LIMIT",
    "session": "NORMAL",
    "price": "37.00",
    "stopPrice": "37.03",
    "duration": "DAY",
    "orderStrategyType": "SINGLE",
    "orderLegCollection": [
     {
      "instruction": "SELL",
      "quantity": 2,
      "instrument": {
       "symbol": "XYZ",
       "assetType": "EQUITY"
      }
     }
    ]
   }
  ]
}
```