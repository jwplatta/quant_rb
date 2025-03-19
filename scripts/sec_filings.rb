require 'json'
require 'net/http'
require 'uri'

class CompanyFacts
  attr_reader :cik, :entity_name, :facts

  def initialize(cik:, entityName:, facts:)
    @cik = cik
    @entity_name = entityName
    @facts = facts
  end

  # Class method to create from hash (similar to Pydantic's model parsing)
  def self.from_hash(hash)
    new(
      cik: hash['cik'],
      entityName: hash['entityName'],
      facts: hash['facts']
    )
  end
end

central_index_key = "CIK0001611052"
url = "https://data.sec.gov/api/xbrl/companyfacts/#{central_index_key}.json"
filename = "#{central_index_key}.json"

# NOTE: This is a sample script to get company facts from the SEC API.
# uri = URI.parse(url)
# request = Net::HTTP::Get.new(uri)
# request["User-Agent"] = "jwplatta@gmail.com"
#
# response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
#   http.request(request)
# end
#
# data = JSON.parse(response.body)
#
# File.open(filename, 'w') do |file|
#   file.write(JSON.pretty_generate(data))
# end

# Read the data from the file
data = JSON.parse(File.read(filename))
company_facts = CompanyFacts.from_hash(data)

puts company_facts.facts['us-gaap']['Assets']

# Print all company attributes
# comp_attrs = company_facts.facts['us-gaap'].keys
# comp_attrs.each do |key|
#   puts key
# end
