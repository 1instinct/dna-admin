FactoryBot.define do
  factory :user, class: 'Spree::User' do
    sequence(:email) { |n| "user#{n}-#{SecureRandom.hex(3)}@example.com" }
    password { 'password123' }
  end

  factory :user_profile, class: 'Spree::UserProfile' do
    user
    sequence(:handle) { |n| "maker#{n}" }
    name { 'Maker' }
  end

  factory :user_block, class: 'Spree::UserBlock' do
    association :blocker, factory: :user
    association :blocked, factory: :user
  end

  factory :content_report, class: 'Spree::ContentReport' do
    association :reporter, factory: :user
    association :reportable, factory: :user_profile
    reason { 'spam' }
  end
end
