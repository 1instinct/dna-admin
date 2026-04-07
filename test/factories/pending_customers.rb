FactoryBot.define do
  factory :pending_customer do
    email { Faker::Internet.unique.email }
    association :spree_user, factory: :spree_user, strategy: :build
    mdi_encounter_id { "enc_#{Faker::Alphanumeric.alphanumeric(number: 10)}" }
    patient_info { { first_name: Faker::Name.first_name, last_name: Faker::Name.last_name } }
  end
end
