FactoryBot.define do
  factory :iap_user, class: 'Spree::User' do
    sequence(:email) { |n| "iap-user-#{n}@example.com" }
    password { 'secret123' }
    password_confirmation { 'secret123' }
  end

  factory :iap_product, class: 'Spree::IapProduct' do
    platform { 'apple' }
    sequence(:product_id) { |n| "example.product.#{n}" }
    kind { 'subscription' }
    entitlement { 'pro' }
    active { true }
  end

  factory :iap_transaction, class: 'Spree::IapTransaction' do
    association :user, factory: :iap_user
    platform { 'apple' }
    sequence(:product_id) { |n| "example.product.#{n}" }
    sequence(:transaction_id) { |n| "txn-#{n}" }
    original_transaction_id { transaction_id }
    environment { 'production' }
    status { 'active' }
    purchased_at { 1.day.ago }
    expires_at { 29.days.from_now }
    verified_at { Time.current }
  end
end
