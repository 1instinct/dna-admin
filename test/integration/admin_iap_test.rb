require 'test_helper'

class AdminIapTest < ActionDispatch::IntegrationTest
  include IapTestHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    setup_iap_config
    @admin = create_user('admin@example.com')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @customer = create_user('customer@example.com')
    @txn = Iap::Recorder.new.record(@customer, 'apple', signed_payload: apple_jws) if iap_product
  end

  test 'the admin menu has an IAP Orders tab' do
    sign_in @admin, scope: :spree_user
    get '/admin/iap_transactions'

    assert_response :ok
    assert_select '#sidebarIapOrders a[href="/admin/iap_transactions"]', text: /IAP Orders/
  end

  test 'IAP Orders lists transactions and filters them' do
    other = create(:iap_transaction, platform: 'google', product_id: GOOGLE_PRODUCT, status: 'expired', environment: 'sandbox')
    sign_in @admin, scope: :spree_user

    get '/admin/iap_transactions'
    assert_select 'td', text: @txn.transaction_id
    assert_select 'td', text: other.transaction_id

    get '/admin/iap_transactions', params: { platform: 'apple', status: 'active', environment: 'production' }
    assert_select 'td', text: @txn.transaction_id
    assert_select 'td', text: other.transaction_id, count: 0

    get '/admin/iap_transactions', params: { email: 'customer@' }
    assert_select 'td', text: other.transaction_id, count: 0

    get '/admin/iap_transactions', params: { product_id: GOOGLE_PRODUCT }
    assert_select 'td', text: @txn.transaction_id, count: 0

    get '/admin/iap_transactions', params: { from: 1.day.from_now.to_date.to_s }
    assert_select 'td', text: @txn.transaction_id, count: 0
  end

  test 'transaction detail shows the decoded payload, user, entitlement and notification history' do
    Spree::IapNotification.create!(platform: 'apple', notification_id: 'n-1', notification_type: 'DID_RENEW',
                                   iap_transaction: @txn, processed_at: Time.current)
    sign_in @admin, scope: :spree_user

    get "/admin/iap_transactions/#{@txn.id}"

    assert_response :ok
    assert_match '&quot;transactionId&quot;: &quot;2000000001&quot;', response.body
    assert_match 'customer@example.com', response.body
    assert_match 'DID_RENEW', response.body
    assert_select '.iap-entitlement', text: /pro/
  end

  test 'manual revoke requires a note, is audited and removes the entitlement' do
    sign_in @admin, scope: :spree_user

    post "/admin/iap_transactions/#{@txn.id}/revoke", params: { note: '  ' }
    assert_redirected_to "/admin/iap_transactions/#{@txn.id}"
    assert_equal 'active', @txn.reload.status

    post "/admin/iap_transactions/#{@txn.id}/revoke", params: { note: 'Chargeback via support' }
    assert_redirected_to "/admin/iap_transactions/#{@txn.id}"
    @txn.reload
    assert_equal 'revoked', @txn.status
    assert @txn.admin_revoked_at
    log = Spree::IapAuditLog.take!
    assert_equal @admin.id, log.admin_user_id
    assert_equal 'revoke', log.action
    assert_equal 'Chargeback via support', log.note
    refute pro?(@customer)
  end

  test 'revoking an entitlement from the user page revokes its granting transactions' do
    sign_in @admin, scope: :spree_user
    ent = entitlement_for(@customer)

    post "/admin/entitlements/#{ent.id}/revoke", params: { note: 'abuse' }

    assert_redirected_to "/admin/users/#{@customer.id}/edit"
    refute pro?(@customer)
    assert_equal 'revoked', @txn.reload.status
    assert_equal 1, Spree::IapAuditLog.count
  end

  test 'the user edit page shows an In-app purchases panel' do
    sign_in @admin, scope: :spree_user
    get "/admin/users/#{@customer.id}/edit"

    assert_response :ok
    assert_select '#admin_user_in_app_purchases' do
      assert_select 'h1', text: /In-app purchases/
      assert_select 'a[href=?]', "/admin/iap_transactions/#{@txn.id}"
      assert_select '.iap-entitlement', text: /pro/
    end
  end

  test 'the user orders page shows the in-app purchases next to Spree orders' do
    sign_in @admin, scope: :spree_user
    get "/admin/users/#{@customer.id}/orders"
    assert_response :ok
    assert_select '#admin_user_in_app_purchases a[href=?]', "/admin/iap_transactions/#{@txn.id}"
  end

  test 'IAP products are admin-editable' do
    sign_in @admin, scope: :spree_user
    get '/admin/iap_products'
    assert_response :ok
    assert_select 'td', text: APPLE_PRODUCT

    post '/admin/iap_products', params: { iap_product: { platform: 'google', product_id: 'example_pro_yearly',
                                                          kind: 'subscription', entitlement: 'pro', name: 'Yearly', active: '1' } }
    assert Spree::IapProduct.find_by(platform: 'google', product_id: 'example_pro_yearly')
  end

  test 'non-admins cannot see IAP pages' do
    sign_in @customer, scope: :spree_user
    get '/admin/iap_transactions'
    assert_response :redirect
    get "/admin/iap_transactions/#{@txn.id}"
    assert_response :redirect
  end
end
