FactoryBot.define do
  factory :pharmacy_order do
    association :patient_mapping
    honeybee_order_number { "HB-#{Faker::Number.unique.number(digits: 6)}" }
    prescription_ids { [Faker::Number.number(digits: 8)] }
    status { "pending" }
    shipment_data { {} }
    exception_data { {} }
  end
end
