require "test_helper"

# v1 controllers accept a user OAuth token (Authorization: Bearer) as well as the
# X-Spree-Token / ?token= api key. Bearer wins when both are sent.
class Spree::Api::V1::BearerAuthTest < ActionDispatch::IntegrationTest
  setup do
    @user = Spree.user_class.create!(email: "bearer#{SecureRandom.hex(4)}@example.com", password: "password123")
    @other = Spree.user_class.create!(email: "other#{SecureRandom.hex(4)}@example.com", password: "password123")
    @user.generate_spree_api_key!
    @other.generate_spree_api_key!

    shipping_category = Spree::ShippingCategory.create!(name: "bearer-#{SecureRandom.hex(4)}")
    product = Spree::Product.new(name: "Bearer Test", price: 10, shipping_category: shipping_category)
    product.stores << Spree::Store.default if product.respond_to?(:stores) && Spree::Store.default.persisted?
    product.save!
    @favorite = Favorite.create!(user: @user, variant: product.master)
  end

  test "valid bearer token resolves the token owner" do
    get "/api/v1/favorites.json", headers: bearer(token_for(@user))
    assert_response :success
    assert_equal [@favorite.id], favorite_ids
  end

  test "bearer token wins over an api key" do
    get "/api/v1/favorites.json", headers: bearer(token_for(@user)).merge("X-Spree-Token" => @other.spree_api_key)
    assert_response :success
    assert_equal [@favorite.id], favorite_ids
  end

  test "bearer token for another user does not see these favorites" do
    get "/api/v1/favorites.json", headers: bearer(token_for(@other))
    assert_response :success
    assert_equal [], favorite_ids
  end

  test "expired bearer token is 401" do
    token = token_for(@user)
    token_record(token).update_column(:created_at, 2.hours.ago)
    get "/api/v1/favorites.json", headers: bearer(token)
    assert_response :unauthorized
  end

  test "revoked bearer token is 401" do
    token = token_for(@user)
    token_record(token).revoke
    get "/api/v1/favorites.json", headers: bearer(token)
    assert_response :unauthorized
  end

  test "unknown bearer token is 401 even with a valid api key" do
    get "/api/v1/favorites.json", headers: bearer("not-a-token").merge("X-Spree-Token" => @user.spree_api_key)
    assert_response :unauthorized
  end

  test "X-Spree-Token api key still works" do
    get "/api/v1/favorites.json", headers: { "X-Spree-Token" => @user.spree_api_key }
    assert_response :success
    assert_equal [@favorite.id], favorite_ids
  end

  test "?token= api key still works" do
    get "/api/v1/favorites.json", params: { token: @user.spree_api_key }
    assert_response :success
    assert_equal [@favorite.id], favorite_ids
  end

  test "invalid api key is still 401" do
    get "/api/v1/favorites.json", headers: { "X-Spree-Token" => "nope" }
    assert_response :unauthorized
  end

  test "no credentials: authenticated endpoint unchanged" do
    get "/api/v1/favorites.json"
    expected = Spree::Api::Config[:requires_authentication] ? :unauthorized : :success
    assert_response expected
  end

  test "no credentials: public endpoint still serves guests" do
    get "/api/v1/menu_items.json"
    assert_response :success
  end

  private

  def token_for(user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: "")
    record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token
  end

  def token_record(plaintext)
    Doorkeeper.config.access_token_model.by_token(plaintext)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def favorite_ids
    JSON.parse(response.body)["data"].map { |f| f["id"] }
  end
end
