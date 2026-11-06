require "test_helper"
require "minitest/mock"

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
    card_row = Spree::CreditCard.with_deleted.find(card.id)
    assert card_row.deleted_at.present?, "unused cards are soft-deleted"
    assert_nil card_row.user_id
    assert_nil card_row.name
    assert_nil card_row.last_digits
    assert_nil card_row.gateway_customer_profile_id
    assert_nil card_row.gateway_payment_profile_id
    deleted = Spree.user_class.with_deleted.find(@user.id)
    assert_nil deleted.bill_address_id
    assert_nil deleted.ship_address_id
  end

  test "a saved card a retained payment uses is detached, not deleted, and the payment still processes" do
    card = create_credit_card(@user)
    card.update_columns(default: true, gateway_customer_profile_id: "BGS-cust")
    completed = create_order({})
    completed.update_columns(state: "complete", completed_at: Time.current)
    to_capture = Spree::Payment.create!(order: completed, amount: 10, payment_method: bogus_gateway, source: card,
                                        state: "pending", response_code: "12345")
    to_void = Spree::Payment.create!(order: completed, amount: 5, payment_method: bogus_gateway, source: card,
                                     state: "pending", response_code: "12345")

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    card_row = Spree::CreditCard.find_by(id: card.id)
    assert card_row, "the card is not soft-deleted"
    assert_nil card_row.user_id
    refute card_row.default
    assert_nil card_row.name, "the cardholder name is cleared"
    assert_equal "1111", card_row.last_digits
    assert_equal "visa", card_row.cc_type
    assert_equal "BGS-cust", card_row.gateway_customer_profile_id
    assert_equal card.gateway_payment_profile_id, card_row.gateway_payment_profile_id

    to_capture.reload
    assert_equal card.id, to_capture.source&.id, "the payment keeps its source"
    assert to_capture.valid?, to_capture.errors.full_messages.to_sentence
    to_capture.capture!
    assert to_capture.reload.completed?
    to_void = Spree::Payment.find(to_void.id)
    assert to_void.source.present?
    to_void.void_transaction!
    assert to_void.reload.void?
  end

  test "a loyalty points payment on a retained order still validates and voids after deletion" do
    @user.update_column(:loyalty_points_balance, 1000)
    completed = create_order({})
    completed.update_columns(state: "complete", completed_at: Time.current)
    loyalty = Spree::PaymentMethod::LoyaltyPoints.create!(name: "Loyalty #{SecureRandom.hex(3)}")
    payment = Spree::Payment.create!(order: completed, amount: 10, payment_method: loyalty, state: "completed")

    delete "/api/v1/account", headers: bearer(@token)
    assert_response :no_content

    payment = Spree::Payment.find(payment.id)
    assert_nil payment.order.user, "sanity: the order's user is soft-deleted"
    assert payment.valid?, payment.errors.full_messages.to_sentence
    payment.void!
    assert payment.reload.void?
  end

  # Spree reuses the user's saved address record on new carts, so a cart can share an address
  # with a completed order.
  { bill: %i[bill_address], ship: %i[ship_address], both: %i[bill_address ship_address] }.each do |label, slots|
    test "a cart with line items sharing an address (#{label}) with a completed order is removed" do
      shared = create_address(@user)
      completed = create_order(bill_address: shared, ship_address: shared)
      completed.update_columns(state: "complete", completed_at: Time.current)
      cart = create_order(slots.map { |slot| [slot, shared] }.to_h)
      add_line_item(cart)

      delete "/api/v1/account", headers: bearer(@token)

      assert_response :no_content
      refute Spree::Order.exists?(cart.id), "the cart is destroyed"
      assert_equal 0, Spree::LineItem.where(order_id: cart.id).count
      assert Spree::Order.exists?(completed.id)
      assert Spree::Address.exists?(shared.id), "the completed order's address is kept"
      assert_nil Spree::Address.find(shared.id).user_id
      assert_equal shared.id, completed.reload.bill_address_id
    end
  end

  test "a cart's own address is removed with the cart" do
    own = create_address(nil)
    cart = create_order(bill_address: own, ship_address: own)
    add_line_item(cart)

    delete "/api/v1/account", headers: bearer(@token)

    assert_response :no_content
    refute Spree::Order.exists?(cart.id)
    refute Spree::Address.exists?(own.id)
  end

  %w[completed pending processing void].each do |state|
    test "an open cart with a #{state} payment is retained and anonymized" do
      cart = create_order({})
      add_line_item(cart)
      Spree::Payment.create!(order: cart, amount: 10, payment_method: check_method, state: state)

      delete "/api/v1/account", headers: bearer(@token)

      assert_response :no_content
      assert Spree::Order.exists?(cart.id), "money may have moved: keep the order"
      assert_equal "deleted-#{@user.id}@invalid", cart.reload.email
    end
  end

  test "an open cart with only failed payments is removed" do
    cart = create_order({})
    Spree::Payment.create!(order: cart, amount: 10, payment_method: check_method, state: "failed")

    delete "/api/v1/account", headers: bearer(@token)

    assert_response :no_content
    refute Spree::Order.exists?(cart.id)
  end

  test "saved checks are soft-deleted; numbers cleared unless a retained payment uses the check" do
    used = create_check(@user)
    unused = create_check(@user)
    completed = create_order({})
    completed.update_columns(state: "complete", completed_at: Time.current)
    payment = Spree::Payment.create!(order: completed, amount: 10, payment_method: check_method, state: "completed")
    payment.update_columns(source_type: "Spree::Check", source_id: used.id)

    delete "/api/v1/account", headers: bearer(@token)

    assert_response :no_content
    used_row = Spree::Check.find(used.id)
    assert used_row.deleted_at.present?
    assert_nil used_row.user_id
    assert_equal "123456789", used_row.account_number, "a retained payment's source stays intact"
    unused_row = Spree::Check.find(unused.id)
    assert unused_row.deleted_at.present?
    assert_nil unused_row.user_id
    assert_nil unused_row.account_number
    assert_nil unused_row.routing_number
    assert_nil unused_row.account_holder_name
  end

  test "an unexpected database error is a 500 and rolls everything back" do
    favorite = Favorite.create!(user: @user, variant: create_product.master)
    Spree::Order.stub(:incomplete, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      delete "/api/v1/account", headers: bearer(@token)
    end

    assert_response :internal_server_error
    assert JSON.parse(response.body)["error"].present?
    assert Spree.user_class.exists?(@user.id)
    assert Favorite.exists?(favorite.id), "content deleted before the error is restored"
    refute token_record(@token).revoked?, "token revocation is rolled back"
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

  def bogus_gateway
    @bogus_gateway ||= Spree::Gateway::Bogus.create!(name: "Bogus #{SecureRandom.hex(3)}")
  end

  def create_order(attrs)
    store = default_store
    Spree::Order.create!({ user: @user, email: @email, store: store, currency: store.default_currency }.merge(attrs))
  end

  # Sourceless payment method, so payments need no card.
  def check_method
    @check_method ||= Spree::PaymentMethod::Check.create!(name: "Check #{SecureRandom.hex(3)}")
  end

  def add_line_item(order)
    product = create_product
    product.update_column(:available_on, 1.day.ago)
    variant = product.master
    variant.update_column(:track_inventory, false)
    Spree::LineItem.create!(order: order, variant: variant, quantity: 1, price: 10,
                            currency: order.currency)
  end

  def create_check(user)
    Spree::Check.create!(user: user, payment_method: bogus_gateway, account_holder_name: "Pat Leaver",
                         account_holder_type: "Individual", account_number: "123456789",
                         routing_number: "021000021")
  end

  def create_credit_card(user)
    gateway = bogus_gateway
    Spree::CreditCard.create!(user: user, payment_method: gateway, name: "Pat Leaver", month: 12,
                              year: Time.current.year + 2, cc_type: "visa", last_digits: "1111",
                              gateway_payment_profile_id: "BGS-#{SecureRandom.hex(3)}")
  end
end
