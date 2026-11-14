FactoryBot.define do
  factory :digital_product, class: 'Spree::Product' do
    sequence(:name) { |n| "Digital Product #{n}" }
    price { 10 }
    available_on { 1.day.ago }
    shipping_category { Spree::ShippingCategory.first_or_create!(name: 'Default') }

    after(:build) do |product|
      product.stores << DigitalAssetsTestHelper.store if product.respond_to?(:stores) && product.stores.empty?
    end
  end

  factory :digital_asset, class: 'Spree::DigitalAsset' do
    variant { create(:digital_product).master }
    kind { 'pack' }
    manifest { {} }
  end

  factory :digital_ownership, class: 'Spree::DigitalOwnership' do
    user
    variant { create(:digital_product).master }
    source { 'grant' }
    granted_at { Time.current }
  end
end
