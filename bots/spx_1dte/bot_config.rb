require 'yaml'
require 'date'
require 'tzinfo'

class BotConfig
  def initialize(config_path)
    raise "Config file not found at #{config_path}" unless File.exist?(config_path)
    @config = YAML.load_file(config_path)
    init_trade_attrs
  end

  def trade_mode
    @config['trade_mode']
  end

  def paper?
    trade_mode == 'paper'
  end

  def live?
    trade_mode == 'live'
  end

  def trading_allowed?(date = Date.today)
    !high_risk_date?(date)
  end

  def high_risk_date?(date)
    high_risk_dates.include?(date)
  end

  def holiday?(date)
    holiday_dates.include?(date)
  end

  def early_close_date?(date)
    early_close_dates.include?(date)
  end

  def monitoring_window(date = Date.today)
    window_entry(@config['monitoring_window'], date)
  end

  def monitoring_start_time(date = Date.today)
    window = monitoring_window(date)
    to_local_time(window[:start_time], window[:timezone])
  end

  def monitoring_end_time(date = Date.today)
    window = monitoring_window(date)
    to_local_time(window[:end_time], window[:timezone])
  end

  def exit_by_time(date = Date.today)
    window = monitoring_window(date)
    to_local_time(window[:exit_by_time], window[:timezone])
  end

  def enter_trade_window(date = Date.today)
    window_entry(@config['enter_trade_window'], date)
  end

  def enter_trade_window_start_time(date = Date.today)
    window = enter_trade_window(date)
    timezone = window[:timezone]
    to_local_time(window[:start_time], timezone)
  end

  def enter_trade_window_end_time(date = Date.today)
    window = enter_trade_window(date)
    timezone = window[:timezone]
    to_local_time(window[:end_time], timezone)
  end

  def low_risk_date?(date)
    !high_risk_date?(date)
  end

  def high_risk_dates
    @high_risk_dates ||= @config['high_risk_dates']
      .map { |entry| Date.parse(entry['date']) }
  end

  def holiday_dates
    @holiday_dates ||= @config['holiday_dates']
      .map { |entry| Date.parse(entry['date']) }
  end

  def early_close_dates
    @early_close_dates ||= @config['early_close_dates']
      .map { |entry| Date.parse(entry['date']) }
  end

  private

  def init_trade_attrs
    if @config.key? "trade"
      @config["trade"].each do |key, value|
        self.class.send(:attr_reader, key.to_sym)
        instance_variable_set("@#{key}", value)
      end
    end
  end

  def window_entry(window_config, date)
    entry = if early_close_date?(date)
      window_config['early_close']
    else
      window_config['default']
    end

    result = {
      start_time: entry['start_time'],
      end_time: entry['end_time'],
      timezone: entry['timezone']
    }

    result[:exit_by_time] = entry['exit_by_time'] if entry.key?('exit_by_time')
    result
  end

  def to_local_time(time, timezone_name = nil)
    start_time = DateTime.strptime(time, '%I:%M %p')

    if timezone_name && !timezone_name.empty?
      timezone = TZInfo::Timezone.get(timezone_name)
      timezone.local_time(
        start_time.year, start_time.month,
        start_time.day, start_time.hour,
        start_time.min, start_time.second
      )
    else
      Time.local(
        start_time.year, start_time.month,
        start_time.day, start_time.hour,
        start_time.min, start_time.second
      )
    end
  end
end
