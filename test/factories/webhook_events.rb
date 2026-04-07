FactoryBot.define do
  factory :webhook_event do
    event_type { "case_approved" }
    source { :mdi }
    payload { { encounter_id: "enc_123" } }
    processed_at { Time.current }
  end
end
