FactoryBot.define do
  factory :review_attribute, class: 'Spree::ReviewAttribute' do
    sequence(:key) { |n| "quality_#{n}" }
    label { 'Quality' }
    kind { 'scale' }

    trait :fit do
      key { 'fit' }
      label { 'Fit' }
      kind { 'bipolar' }
      low_label { 'Runs small' }
      high_label { 'Runs large' }
    end
  end
end
