FactoryBot.define do
  factory :affiliate_account do
    user
    sequence(:code) { |n| "affiliate-#{n}" }
    status { 'pending' }
    payout_email { 'payouts@example.com' }
    application { { 'website' => 'https://example.com', 'audience' => 'Producers', 'channels' => %w[youtube], 'message' => 'Hi' } }

    trait :approved do
      status { 'approved' }
      approved_at { Time.current }
    end
  end

  factory :affiliate_click do
    affiliate_account
    landing_path { '/' }
  end

  factory :affiliate_payout do
    affiliate_account
    amount { 10 }
    currency { 'USD' }
    reference { 'REF-1' }
    paid_at { Time.current }
  end

  factory :affiliate_commission do
    affiliate_account
    order do
      store = Spree::Store.default
      unless store.persisted?
        store = Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "test-#{SecureRandom.hex(3)}",
                                     mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
      end
      Spree::Order.create!(email: 'buyer@example.com', store: store, currency: 'USD')
    end
    base_amount { 100 }
    commission_bps { 1000 }
    amount { 10 }
    currency { 'USD' }
    state { 'pending' }
    approvable_at { 30.days.from_now }
  end
end
