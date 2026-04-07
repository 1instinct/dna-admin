FactoryBot.define do
  factory :patient_mapping do
    honeybee_patient_id { "HB-PAT-#{Faker::Number.unique.number(digits: 6)}" }
    email { Faker::Internet.email }
    source { :rx_received }
    history { [] }
  end
end
