require "test_helper"

class StoresSeedTest < ActiveSupport::TestCase
  setup do
    # Clear existing stores
    Spree::Store.destroy_all
    # Run seed
    load Rails.root.join("db/seeds/stores.rb")
  end

  test "creates exactly 5 stores" do
    assert_equal 5, Spree::Store.count
  end

  test "creates English/USD store as default" do
    store = Spree::Store.find_by(code: "cntrl-en")
    assert store.present?
    assert_equal "en", store.default_locale
    assert_equal "USD", store.default_currency
    assert store.default, "cntrl-en should be the default store"
  end

  test "creates German/EUR store" do
    store = Spree::Store.find_by(code: "cntrl-de")
    assert store.present?
    assert_equal "de", store.default_locale
    assert_equal "EUR", store.default_currency
    assert_not store.default
  end

  test "creates French/EUR store" do
    store = Spree::Store.find_by(code: "cntrl-fr")
    assert store.present?
    assert_equal "fr", store.default_locale
    assert_equal "EUR", store.default_currency
    assert_not store.default
  end

  test "creates Italian/EUR store" do
    store = Spree::Store.find_by(code: "cntrl-it")
    assert store.present?
    assert_equal "it", store.default_locale
    assert_equal "EUR", store.default_currency
    assert_not store.default
  end

  test "creates Spanish/EUR store" do
    store = Spree::Store.find_by(code: "cntrl-es")
    assert store.present?
    assert_equal "es", store.default_locale
    assert_equal "EUR", store.default_currency
    assert_not store.default
  end

  test "all stores have supported_currencies configured" do
    Spree::Store.all.each do |store|
      assert store.supported_currencies.present?,
        "#{store.code} should have supported_currencies"
    end
  end

  test "seed is idempotent" do
    # Run seed again
    load Rails.root.join("db/seeds/stores.rb")
    assert_equal 5, Spree::Store.count, "Running seed twice should not create duplicates"
  end
end
