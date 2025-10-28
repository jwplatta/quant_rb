require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::MonotonicityEnforcer do
  let(:expiration_date) { Date.today + 1 }

  def create_option(strike:, mark:, contract_type:, underlying_price:, expiration_date:)
    OptionsTrader::DataObjects::Option.new(
      symbol: "SPX#{expiration_date.strftime('%y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i}",
      underlying_symbol: 'SPX',
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: 1,
      timestamp: Time.now
    )
  end

  describe 'edge cases' do
    let(:underlying_price) { 5800 } # ATM

    it 'handles empty array' do
      result = described_class.enforce([], underlying_price, method: 'remove')
      expect(result).to eq([])
    end

    it 'handles single option' do
      calls = [create_option(
        strike: 5900, mark: 28.0,
        contract_type: 'CALL',
        underlying_price: underlying_price,
        expiration_date: expiration_date
      )]
      result = described_class.enforce(calls, underlying_price, method: 'remove')

      expect(result.length).to eq(1)
      expect(result.first.mark).to eq(28.0)
    end

    it 'handles options with nil marks' do
      calls = [
        create_option(
          strike: 5805,
          mark: 120.0,
          contract_type: 'CALL',
          underlying_price: underlying_price,
          expiration_date: expiration_date
        ),
        create_option(
          strike: 5850,
          mark: nil,
          contract_type: 'CALL',
          underlying_price: underlying_price, expiration_date: expiration_date
        ),
        create_option(
          strike: 5900, mark: 28.0,
          contract_type: 'CALL',
          underlying_price: underlying_price, expiration_date: expiration_date
        )
      ]

      result = described_class.enforce(calls, underlying_price, method: 'remove')

      expect(result.find { |c| c.strike == 5805 }.mark).to eq(120.0)
      expect(result.find { |c| c.strike == 5850 }.mark).to be_nil
      expect(result.find { |c| c.strike == 5900 }.mark).to eq(28.0)
    end
  end

  describe 'PUT option monotonicity enforcement' do
    let(:underlying_price) { 6875.16 } # ATM
    let(:expiration_date) { Date.parse("2025-10-28") }
    let(:put_opts) do
      [
        create_option(
          strike: 6830, mark: 2.7,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6840, mark: 3.3,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6845, mark: 3.85,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6855, mark: 5.05,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6860, mark: 5.04,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6870, mark: 9.8,
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6880, mark: 11.7, # 6.86 extrinsic
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6885, mark: 14.2, # 4.36 extrinsic
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6890, mark: 14.2, # 4.36 extrinsic
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6895, mark: 25.0, # 5.16 extrinsic
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6900, mark: 23.9, # extrinsic -0.94
          underlying_price: underlying_price, contract_type: 'PUT',
          expiration_date: expiration_date
        ),
      ]
    end
    let(:enforcer) do
      described_class.new(
        underlying_price: underlying_price,
        method: 'remove'
      )
    end

    it 'removes OTM violations' do
      result = enforcer.fix_otm_puts(put_opts)
      expect(result.count).to eq(6)
      expect(result.find { |p| p.strike == 6830 }.mark).to eq(2.7)
      expect(result.find { |p| p.strike == 6840 }.mark).to eq(3.3)
      expect(result.find { |p| p.strike == 6845 }.mark).to eq(3.85)
      expect(result.find { |p| p.strike == 6855 }.mark).to eq(5.05)
      expect(result.find { |p| p.strike == 6860 }.mark).to eq(nil)
      expect(result.find { |p| p.strike == 6870 }.mark).to eq(9.8)
    end

    it 'removes ITM violations' do
      result = enforcer.fix_itm_puts(put_opts)
      expect(result.count).to eq(5)
      expect(result.find { |p| p.strike == 6880 }.mark).to eq(11.7)
      expect(result.find { |p| p.strike == 6885 }.mark).to eq(14.2)
      expect(result.find { |p| p.strike == 6890 }.mark).to eq(14.2)
      expect(result.find { |p| p.strike == 6895 }.mark).to eq(nil)
      expect(result.find { |p| p.strike == 6900 }.mark).to eq(23.9)
    end
    describe '#enforce' do
      it 'does not raise' do
        expect { enforcer.enforce(put_opts) }.not_to raise_error(
          OptionsTrader::SyntheticData::Transform::MonotonicityViolationError
        )
      end

      it 'raises error on unresolvable violations' do
        bad_option = create_option(
          strike: 6875, mark: 11.8,
          underlying_price: underlying_price,
          contract_type: 'PUT',
          expiration_date: expiration_date
        )
        expect { enforcer.enforce(put_opts << bad_option) }.to raise_error(
          OptionsTrader::SyntheticData::Transform::MonotonicityViolationError
        )
      end
    end
  end

  describe 'CALL option monotonicity enforcement' do
    let(:underlying_price) { 6858.0 } # ATM
    let(:expiration_date) { Date.parse("2025-10-28") }
    let(:call_opts) do
      [
        create_option(
          strike: 6840, mark: 19.01, # instrinsic is 18.0
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6845, mark: 13.5, # instrinsic is 13.0
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6850, mark: 14.00, # instrinsic is 8.0 and extrinsic is 3.0
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6855, mark: 13.08, # instrinsic is 3.0 and extrinsic is 10.08
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        ### ATM
        create_option(
          strike: 6865, mark: 10.9,
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6870, mark: 11.0,
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6875, mark: 6.5,
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
        create_option(
          strike: 6880, mark: 6.5,
          underlying_price: underlying_price, contract_type: 'CALL',
          expiration_date: expiration_date
        ),
      ]
    end
    let(:enforcer) do
      described_class.new(
        underlying_price: underlying_price,
        method: 'remove'
      )
    end

    it 'removes OTM violations' do
      result = enforcer.fix_otm_calls(call_opts)
      expect(result.count).to eq(4)
      expect(result.find { |c| c.strike == 6865 }.mark).to eq(10.9)
      expect(result.find { |c| c.strike == 6870 }.mark).to eq(nil)
      expect(result.find { |c| c.strike == 6875 }.mark).to eq(6.5)
      expect(result.find { |c| c.strike == 6880 }.mark).to eq(6.5)
    end

    it 'removes ITM violations' do
      result = enforcer.fix_itm_calls(call_opts)
      expect(result.count).to eq(4)
      expect(result.find { |c| c.strike == 6840 }.mark).to eq(19.01)
      expect(result.find { |c| c.strike == 6845 }.mark).to eq(nil)
      expect(result.find { |c| c.strike == 6850 }.mark).to eq(14.00)
      expect(result.find { |c| c.strike == 6855 }.mark).to eq(13.08)
    end

    describe '#enforce' do
      it 'does not raise' do
        expect { enforcer.enforce(call_opts) }.not_to raise_error(
          OptionsTrader::SyntheticData::Transform::MonotonicityViolationError
        )
      end
      it 'raises error on unresolvable violations' do
        bad_option = create_option(
          strike: 6860, mark: 14.0,
          underlying_price: underlying_price,
          contract_type: 'CALL',
          expiration_date: expiration_date
        )
        expect { enforcer.enforce(call_opts << bad_option) }.to raise_error(
          OptionsTrader::SyntheticData::Transform::MonotonicityViolationError
        )
      end
    end
  end
end
