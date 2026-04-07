FactoryBot.define do
  factory :prescription do
    association :patient_mapping
    prescription_id { Faker::Number.unique.number(digits: 8) }
    drug_name { "Pessary Device" }
    ndc { "02400000713" }
    written_qty { 1 }
    refills_left { 0 }
    expire_date { 1.year.from_now.to_date }
    prescriber_name { Faker::Name.name }
    status { :pending }
    received_at { Time.current }
  end
end
