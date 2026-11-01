require "test_helper"

# DELETE /api/v1/account: the signed-in user deletes their own account (app-store account
# deletion). OAuth bearer required. 204 deleted, 401 no/invalid/revoked token, 422 { error } refused.
class Spree::Api::V1::AccountControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "password123".freeze

  setup do
    @email = "leaver#{SecureRandom.hex(4)}@example.com"
    @user = Spree.user_class.create!(email: @email, password: PASSWORD)
    @user.generate_spree_api_key!
    @token = token_for(@user)
  end

  test "deletes the account: 204, tokens and grants revoked, user soft-deleted and anonymized" do
    other_token = token_for(@user)
    grant = create_grant(@user)

    delete "/api/v1/account", headers: bearer(@token)

    assert_response :no_content
    assert_empty response.body

    tokens = Doorkeeper.config.access_token_model.where(resource_owner_id: @user.id)
    assert_equal 2, tokens.count
    assert tokens.all?(&:revoked?), "every access token is revoked"
    assert token_record(other_token).revoked?
    assert grant.reload.revoked?, "access grants are revoked"

    assert_nil Spree.user_class.find_by(id: @user.id), "user is hidden by the paranoid default scope"
    deleted = Spree.user_class.with_deleted.find(@user.id)
    assert deleted.deleted_at.present?
    assert_equal "deleted-#{@user.id}@invalid", deleted.email
    assert_nil deleted.login
    assert_nil deleted.spree_api_key
    assert_nil deleted.last_sign_in_ip
    assert_nil deleted.current_sign_in_ip
    refute deleted.valid_password?(PASSWORD), "old password no longer matches"
  end

  test "the path also answers with an explicit .json format" do
    delete "/api/v1/account.json", headers: bearer(@token)
    assert_response :no_content
  end

  test "a repeat call with the same token is 401" do
    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :unauthorized
  end

  test "the deleted user can no longer sign in" do
    post "/spree_oauth/token", params: { grant_type: "password", username: @email, password: PASSWORD }
    assert_response :success, "sanity: password grant works before deletion"

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    post "/spree_oauth/token", params: { grant_type: "password", username: @email, password: PASSWORD }
    refute_equal 200, response.status
    assert_nil JSON.parse(response.body)["access_token"]
  end

  test "the original email can sign up again" do
    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    fresh = Spree.user_class.create!(email: @email, password: "another-pass-1")
    refute_equal @user.id, fresh.id
    assert_equal @email, fresh.email
  end

  test "deletes the user's own content" do
    other = Spree.user_class.create!(email: "friend#{SecureRandom.hex(4)}@example.com", password: PASSWORD)
    variant = create_product.master
    Favorite.create!(user: @user, variant: variant)
    other_favorite = Favorite.create!(user: other, variant: variant)
    UserFollow.create!(follower: @user, following: other)
    UserFollow.create!(follower: other, following: @user)
    stream = LiveStream.create!(title: "stream")
    LiveStreamLike.create!(live_stream: stream, user: @user)
    Message.create!(sender: @user, receiver: other, message: "hi")
    Message.create!(sender: other, receiver: @user, message: "hello")

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    assert_equal 0, Favorite.where(user_id: @user.id).count
    assert Favorite.exists?(other_favorite.id), "other users' favorites stay"
    assert_equal 0, UserFollow.where(follower_id: @user.id).or(UserFollow.where(following_id: @user.id)).count
    assert_equal 0, LiveStreamLike.where(user_id: @user.id).count
    assert_equal 0, Message.where(sender_type: @user.class.name, sender_id: @user.id).count
    assert_equal 0, Message.where(receiver_type: @user.class.name, receiver_id: @user.id).count
    assert Spree.user_class.exists?(other.id)
  end

  test "completed orders are retained but anonymized; unused addresses and saved cards go" do
    store = default_store
    order_address = create_address(@user)
    spare_address = create_address(@user)
    @user.update_columns(bill_address_id: spare_address.id, ship_address_id: order_address.id)
    order = Spree::Order.create!(user: @user, email: @email, store: store, currency: store.default_currency,
                                 bill_address: order_address, ship_address: order_address)
    order.update_columns(state: "complete", completed_at: Time.current, last_ip_address: "203.0.113.9")
    cart = Spree::Order.create!(user: @user, email: @email, store: store, currency: store.default_currency)
    card = create_credit_card(@user)

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    order.reload
    assert_equal @user.id, order.user_id, "the completed order keeps its (soft-deleted) owner"
    assert_equal "deleted-#{@user.id}@invalid", order.email
    assert_nil order.last_ip_address
    assert Spree::Address.exists?(order_address.id), "addresses on completed orders are kept for accounting"
    assert_nil Spree::Address.find(order_address.id).user_id, "...but leave the deleted user's address book"
    refute Spree::Address.exists?(spare_address.id), "addresses no order uses are destroyed"
    refute Spree::Order.exists?(cart.id), "an open cart without payments is destroyed"
    assert_nil Spree::CreditCard.find_by(id: card.id), "saved cards are destroyed"
    deleted = Spree.user_class.with_deleted.find(@user.id)
    assert_nil deleted.bill_address_id
    assert_nil deleted.ship_address_id
  end

  test "401 without a token" do
    delete "/api/v1/account"
    assert_response :unauthorized
    assert Spree.user_class.exists?(@user.id)
  end

  test "401 with an unknown token" do
    delete "/api/v1/account", headers: bearer("not-a-token")
    assert_response :unauthorized
    assert Spree.user_class.exists?(@user.id)
  end

  test "401 with a revoked token" do
    token_record(@token).revoke
    delete "/api/v1/account", headers: bearer(@token)
    assert_response :unauthorized
    assert Spree.user_class.exists?(@user.id)
  end

  test "401 with only an api key (bearer required)" do
    delete "/api/v1/account", headers: { "X-Spree-Token" => @user.spree_api_key }
    assert_response :unauthorized
    assert Spree.user_class.exists?(@user.id)
  end

  test "admins are refused with 422 and a message" do
    @user.spree_roles << Spree::Role.find_or_create_by!(name: "admin")

    delete "/api/v1/account", headers: bearer(@token)

    assert_response :unprocessable_entity
    error = JSON.parse(response.body)["error"]
    assert error.is_a?(String) && error.strip.present?
    user = Spree.user_class.find(@user.id)
    assert_equal @email, user.email
    refute token_record(@token).revoked?, "a refused deletion changes nothing"
  end

  test "writes an audit log line with the user id and no email" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original = Rails.logger
    Rails.logger = logger
    begin
      delete "/api/v1/account", headers: bearer(@token)
    ensure
      Rails.logger = original
    end
    assert_response :no_content
    line = io.string.lines.grep(/account_deletion/).first
    assert line, "an account_deletion line is logged"
    assert_includes line, "user_id=#{@user.id}"
    refute_includes line, @email
  end

  private

  def token_for(user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: "")
    record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token
  end

  def token_record(plaintext)
    Doorkeeper.config.access_token_model.by_token(plaintext)
  end

  def create_grant(user)
    app = Doorkeeper.config.application_model.create!(name: "app-#{SecureRandom.hex(3)}", redirect_uri: "https://example.com/cb")
    Doorkeeper.config.access_grant_model.create!(resource_owner_id: user.id, application: app, expires_in: 600,
                                                 redirect_uri: "https://example.com/cb", scopes: "")
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def default_store
    store = Spree::Store.default
    return store if store.persisted?

    Spree::Store.create!(name: "Test Store", url: "test.example.com", code: "test-#{SecureRandom.hex(3)}",
                         mail_from_address: "store@example.com", default_currency: "USD", default: true)
  end

  def create_product
    shipping_category = Spree::ShippingCategory.create!(name: "acct-#{SecureRandom.hex(4)}")
    product = Spree::Product.new(name: "Account Test", price: 10, shipping_category: shipping_category)
    product.stores << default_store if product.respond_to?(:stores)
    product.save!
    product
  end

  def country
    @country ||= Spree::Country.find_by(iso: "ZZ") ||
                 Spree::Country.create!(name: "Testland", iso: "ZZ", iso3: "ZZZ", iso_name: "TESTLAND",
                                        states_required: false, zipcode_required: false)
  end

  def create_address(user)
    Spree::Address.create!(user: user, firstname: "Pat", lastname: "Leaver", address1: "1 Main St",
                           city: "Town", zipcode: "12345", phone: "555-0100", country: country)
  end

  def create_credit_card(user)
    gateway = Spree::Gateway::Bogus.create!(name: "Bogus #{SecureRandom.hex(3)}")
    Spree::CreditCard.create!(user: user, payment_method: gateway, name: "Pat Leaver", month: 12,
                              year: Time.current.year + 2, cc_type: "visa", last_digits: "1111",
                              gateway_payment_profile_id: "BGS-#{SecureRandom.hex(3)}")
  end
end
