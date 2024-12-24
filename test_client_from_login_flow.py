import os
from dotenv import load_dotenv
import httpx
from schwab.auth import client_from_login_flow, client_from_manual_flow, client_from_token_file

load_dotenv('.env')

print(os.getcwd())

c = client_from_login_flow(
    api_key=os.getenv('SCHWAB_APP_KEY'),
    app_secret=os.getenv('SCHWAB_APP_SECRET'),
    callback_url=os.getenv('SCHWAB_CALLBACK_URI'),
    token_path='/Users/jplatta/repos/investing/tmp/token.json'
)

print(c.token_metadata.token)

resp = c.get_price_history_every_day('AAPL')
assert resp.status_code == httpx.codes.OK
history = resp.json()
print(history)
