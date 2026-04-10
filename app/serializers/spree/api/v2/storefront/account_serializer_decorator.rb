Spree::V2::Storefront::UserSerializer.class_eval do
  attribute :consultation_status
  attribute :consultation_completed_at
  attribute :consultation_passed do |user|
    user.consultation_passed?
  end
end
