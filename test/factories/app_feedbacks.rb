FactoryBot.define do
  factory :app_feedback, class: 'AppFeedback' do
    kind { 'bug' }
    message { 'The sequencer stopped when I rotated the phone' }
    sequence(:install_id) { |n| "install-#{n}-#{SecureRandom.hex(4)}" }
    platform { 'ios' }
    app_version { '1.2.0' }
    build_number { '42' }
  end
end
