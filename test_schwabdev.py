import os
from dotenv import load_dotenv
import schwabdev

load_dotenv('.env')

schwab_api_key = os.getenv('SCHWAB_APP_KEY')
schwab_app_secret = os.getenv('SCHWAB_APP_SECRET')
schwab_callback_uri = os.getenv('SCHWAB_CALLBACK_URI')

print(schwab_api_key)
client = schwabdev.Client(
  schwab_api_key,
  schwab_app_secret
)

print(client.account_linked().json()) #make api calls
