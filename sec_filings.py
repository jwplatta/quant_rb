import json
import requests
from pydantic import BaseModel

class CompanyFacts(BaseModel):
  cik: int
  entityName: str
  facts: dict

central_index_key = "CIK0001611052"
URL = f'https://data.sec.gov/api/xbrl/companyfacts/{}.json'
filename = f'{central_index_key}.json'
# NOTE: This is a sample script to get company facts from the SEC API.
# headers = {
#   "User-Agent": "jwplatta@gmail.com"
# }
# response = requests.get(URL, headers=headers)
# data = response.json()
# print(data)

# with open(filename, 'w') as f:
#     json.dump(data, f)


with open(filename, 'r') as f:
    data = json.load(f)
    company_facts = CompanyFacts(**data)

print(
   company_facts.facts['us-gaap']['Assets']
)
# comp_attrs = company_facts.facts['us-gaap'].keys()

# for key in comp_attrs:
#     print(key)
# facts = data['facts']
# gaap = data['us-gaap']
# for key in facts.keys():
#     print(key)
