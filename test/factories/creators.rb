FactoryBot.define do
  factory :creator_application, class: 'Spree::CreatorApplication' do
    user
    display_name { 'Night Shift' }
    kinds { %w[pack] }
    portfolio_links { [{ 'label' => 'Site', 'url' => 'https://example.com/work' }] }
    about { 'I make drum sounds.' }
  end

  factory :creator_account, class: 'Spree::CreatorAccount' do
    user
    payout_email { 'payouts@example.com' }
  end

  factory :creator_earning, class: 'Spree::CreatorEarning' do
    creator_account
    sequence(:order_id) { |n| 100_000 + n }
    sequence(:line_item_id) { |n| 100_000 + n }
    gross { 10 }
    share_bps { 7000 }
    amount { 7 }
    currency { 'USD' }
    state { 'pending' }
    payable_at { 14.days.from_now }
  end
end
