require 'yaml'

class BotConfig
  def initialize(config_path)
    raise "Config file not found at #{config_path}" unless File.exist?(config_path)
    @config = YAML.load_file(config_path)
  end

  def trading_allowed?(date = Date.today)
    !high_risk_date?(date)
  end

  def high_risk_date?(date)
    high_risk_dates.include?(date)
  end

  def high_risk_dates
    @high_risk_dates ||= @config['high_risk_dates']
      .map { |entry| Date.parse(entry['date']) }
  end
end
