module ConsultationGate
  extend ActiveSupport::Concern

  def can_purchase?(user)
    return true unless requires_consultation?
    return false unless user&.consultation_passed?
    true
  end
end
