# frozen_string_literal: true

module RiskAssessable
  def risk_status
    if delta.abs < 0.16
      'GREEN'
    elsif delta.abs < 0.26
      'YELLOW'
    else
      'RED'
    end
  end

  def tested?
    risk_status == 'YELLOW'
  end

  def danger?
    risk_status == 'RED'
  end
end
