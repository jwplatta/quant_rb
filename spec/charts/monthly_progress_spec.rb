# frozen_string_literal: true

require 'rspec'

RSpec.describe OptionsTrader::Charts::MonthlyProgress do
  let(:mock_schwab_client) { double('SchwabClient') }
  let(:mock_orders) { [] }
  let(:mock_transactions) { [] }

  before do
    allow(mock_schwab_client).to receive(:set_account)
    allow(mock_schwab_client).to receive(:account_orders).and_return(mock_orders)
    allow(mock_schwab_client).to receive(:transactions).and_return(mock_transactions)
    allow(File).to receive(:join).and_return('tmp/test_chart.png')
    allow(FileUtils).to receive(:mkdir_p)

    mock_chart = double('Chart')
    allow(mock_chart).to receive(:title=)
    allow(mock_chart).to receive(:title_font_size=)
    allow(mock_chart).to receive(:theme=)
    allow(mock_chart).to receive(:data)
    allow(mock_chart).to receive(:labels=)
    allow(mock_chart).to receive(:hide_line_markers=)
    allow(mock_chart).to receive(:show_labels_for_bar_values=)
    allow(mock_chart).to receive(:label_rotation=)
    allow(mock_chart).to receive(:marker_font_size=)
    allow(mock_chart).to receive(:legend_font_size=)
    allow(mock_chart).to receive(:hide_legend=)
    allow(mock_chart).to receive(:y_axis_label=)
    allow(mock_chart).to receive(:x_axis_label=)
    allow(mock_chart).to receive(:write)

    allow(Gruff::Bar).to receive(:new).and_return(mock_chart)
  end

  describe '#initialize' do
    it 'accepts a single account name' do
      chart = described_class.new(mock_schwab_client, account_names: ['main'])
      expect(chart.instance_variable_get(:@account_names)).to eq(['main'])
    end

    it 'accepts multiple account names' do
      chart = described_class.new(mock_schwab_client, account_names: ['main', 'trading'])
      expect(chart.instance_variable_get(:@account_names)).to eq(['main', 'trading'])
    end

    it 'handles empty account names array' do
      chart = described_class.new(mock_schwab_client, account_names: [])
      expect(chart.instance_variable_get(:@account_names)).to eq([])
    end
  end

  describe '#generate' do
    let(:chart) { described_class.new(mock_schwab_client, account_names: ['main']) }

    context 'with empty accounts' do
      let(:chart) { described_class.new(mock_schwab_client, account_names: []) }

      it 'raises an error when no accounts are specified' do
        expect {
          chart.generate(year: 2025)
        }.to raise_error(ArgumentError, "No accounts specified for monthly progress chart")
      end
    end

    context 'with single account' do
      it 'generates a chart for a single account' do
        # Mock data that would come from monthly_totals
        mock_monthly_data = (1..12).map { |month| [Date.new(2025, month, 1), 100.0] }
        allow(chart).to receive(:monthly_totals).and_return(mock_monthly_data)

        expect(mock_schwab_client).to receive(:set_account).with('main')

        filepath = chart.generate(year: 2025)
        expect(filepath).to eq('tmp/test_chart.png')
      end

      it 'uses account_name parameter when provided' do
        mock_monthly_data = (1..12).map { |month| [Date.new(2025, month, 1), 100.0] }
        allow(chart).to receive(:monthly_totals).and_return(mock_monthly_data)

        expect(mock_schwab_client).to receive(:set_account).with('trading')

        chart.generate(year: 2025, account_name: 'trading')
      end
    end

    context 'with multiple accounts' do
      let(:chart) { described_class.new(mock_schwab_client, account_names: ['main', 'trading']) }

      it 'generates a combined chart for multiple accounts' do
        mock_monthly_data_main = (1..12).map { |month| [Date.new(2025, month, 1), 100.0] }
        mock_monthly_data_trading = (1..12).map { |month| [Date.new(2025, month, 1), 200.0] }

        allow(chart).to receive(:monthly_totals).and_return(mock_monthly_data_main, mock_monthly_data_trading)

        expect(mock_schwab_client).to receive(:set_account).with('main')
        expect(mock_schwab_client).to receive(:set_account).with('trading')

        filepath = chart.generate(year: 2025)
        expect(filepath).to eq('tmp/test_chart.png')
      end
    end
  end

  describe 'private methods' do
    let(:chart) { described_class.new(mock_schwab_client, account_names: ['main']) }

    describe '#validate_data!' do
      it 'validates correct data format' do
        data = [[Date.new(2025, 1, 1), 100.0], [Date.new(2025, 2, 1), 200.0]]
        expect { chart.send(:validate_data!, data) }.not_to raise_error
      end

      it 'raises error for empty data' do
        expect {
          chart.send(:validate_data!, [])
        }.to raise_error(ArgumentError, "Data cannot be empty")
      end

      it 'raises error for incorrect array format' do
        expect {
          chart.send(:validate_data!, [['wrong']])
        }.to raise_error(ArgumentError, /must be an array with 2 elements/)
      end

      it 'raises error for non-date first element' do
        expect {
          chart.send(:validate_data!, [['not_date', 100.0]])
        }.to raise_error(ArgumentError, /must be a Date object/)
      end

      it 'raises error for non-numeric second element' do
        expect {
          chart.send(:validate_data!, [[Date.new(2025, 1, 1), 'not_numeric']])
        }.to raise_error(ArgumentError, /must be numeric/)
      end
    end
  end
end
