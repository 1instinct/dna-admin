FactoryBot.define do
  factory :spree_user, class: "Spree::User" do
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
  end
end
