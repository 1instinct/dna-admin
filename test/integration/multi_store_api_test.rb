require "test_helper"

class MultiStoreApiTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure stores exist
    load Rails.root.join("db/seeds/stores.rb")

    @us_store = Spree::Store.find_by!(code: "cntrl-en")
    @de_store = Spree::Store.find_by!(code: "cntrl-de")

    # Create a taxonomy (required for Spree products)
    @taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Categories") do |t|
      t.store = @us_store
    end

    # Create US-only product
    @us_product = create_store_product(
      name: "US Health Kit",
      store: @us_store,
      currency: "USD",
      price: 99.99
    )

    # Create DE-only product
    @de_product = create_store_product(
      name: "DE Gesundheitskit",
      store: @de_store,
      currency: "EUR",
      price: 89.99
    )
  end

  test "US store returns only US products" do
    get "/api/v2/storefront/products",
      headers: { "X-Spree-Store" => "cntrl-en" }

    assert_response :success
    data = JSON.parse(response.body)["data"]
    product_names = data.map { |p| p.dig("attributes", "name") }

    assert_includes product_names, "US Health Kit"
    assert_not_includes product_names, "DE Gesundheitskit"
  end

  test "DE store returns only DE products" do
    get "/api/v2/storefront/products",
      headers: { "X-Spree-Store" => "cntrl-de" }

    assert_response :success
    data = JSON.parse(response.body)["data"]
    product_names = data.map { |p| p.dig("attributes", "name") }

    assert_includes product_names, "DE Gesundheitskit"
    assert_not_includes product_names, "US Health Kit"
  end

  test "US store returns USD prices" do
    get "/api/v2/storefront/products",
      headers: { "X-Spree-Store" => "cntrl-en" }

    assert_response :success
    data = JSON.parse(response.body)["data"]
    us_item = data.find { |p| p.dig("attributes", "name") == "US Health Kit" }
    assert_equal "USD", us_item.dig("attributes", "currency")
    assert_equal "99.99", us_item.dig("attributes", "price")
  end

  test "DE store returns EUR prices" do
    get "/api/v2/storefront/products",
      headers: { "X-Spree-Store" => "cntrl-de" }

    assert_response :success
    data = JSON.parse(response.body)["data"]
    de_item = data.find { |p| p.dig("attributes", "name") == "DE Gesundheitskit" }
    assert_equal "EUR", de_item.dig("attributes", "currency")
    assert_equal "89.99", de_item.dig("attributes", "price")
  end

  test "invalid store code returns default store products" do
    get "/api/v2/storefront/products",
      headers: { "X-Spree-Store" => "nonexistent" }

    # Spree falls back to default store
    assert_response :success
  end

  private

  def create_store_product(name:, store:, currency:, price:)
    product = Spree::Product.create!(
      name: name,
      price: price,
      shipping_category: Spree::ShippingCategory.first_or_create!(name: "Default"),
      available_on: 1.day.ago
    )
    product.stores << store unless product.stores.include?(store)

    # Ensure price exists for the correct currency
    master_variant = product.master
    master_variant.prices.find_or_create_by!(currency: currency) do |p|
      p.amount = price
    end

    product
  end
end
