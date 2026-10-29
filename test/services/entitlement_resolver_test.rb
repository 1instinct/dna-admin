require 'test_helper'

class EntitlementResolverTest < ActiveSupport::TestCase
  include IapTestHelpers

  setup do
    @product = iap_product
    @user = create_user
  end

  def txn(attrs = {})
    Spree::IapTransaction.create!({
      user: @user, iap_product: @product, platform: 'apple', product_id: @product.product_id,
      transaction_id: SecureRandom.hex(6), original_transaction_id: 'orig-1', environment: 'production',
      status: 'active', purchased_at: 1.day.ago, expires_at: 29.days.from_now, verified_at: Time.current
    }.merge(attrs))
  end

  test 'an active, unexpired transaction grants the entitlement' do
    t = txn
    EntitlementResolver.refresh(@user)

    ent = entitlement_for(@user)
    assert ent.active
    assert_equal t, ent.iap_transaction
    assert_equal t.expires_at.to_i, ent.expires_at.to_i
    assert pro?(@user)
  end

  test 'the entitlement runs to the latest expiry among granting transactions' do
    txn(expires_at: 5.days.from_now)
    late = txn(expires_at: 60.days.from_now)
    EntitlementResolver.refresh(@user)

    assert_equal late.expires_at.to_i, entitlement_for(@user).expires_at.to_i
  end

  test 'expiry passing makes the entitlement non-current without a refresh' do
    txn(expires_at: 1.hour.from_now)
    EntitlementResolver.refresh(@user)
    assert pro?(@user)

    travel 2.hours do
      refute pro?(@user)
      EntitlementResolver.refresh(@user)
      refute entitlement_for(@user).active
    end
  end

  test 'grace grants until the grace end, billing retry, refunds and revocations do not' do
    txn(status: 'grace', expires_at: 1.day.ago, grace_expires_at: 3.days.from_now)
    EntitlementResolver.refresh(@user)
    assert pro?(@user)
    assert_in_delta 3.days.from_now.to_i, entitlement_for(@user).expires_at.to_i, 5

    Spree::IapTransaction.update_all(status: 'billing_retry')
    EntitlementResolver.refresh(@user)
    refute pro?(@user)

    %w[refunded revoked expired pending].each do |status|
      Spree::IapTransaction.update_all(status: status, expires_at: 10.days.from_now)
      EntitlementResolver.refresh(@user)
      refute pro?(@user), "#{status} must not grant"
    end
  end

  test 'non-consumables grant without expiry' do
    lifetime = iap_product(product_id: 'example.lifetime', kind: 'non_consumable')
    txn(iap_product: lifetime, product_id: lifetime.product_id, expires_at: nil)
    EntitlementResolver.refresh(@user)

    assert_nil entitlement_for(@user).expires_at
    assert pro?(@user)
  end

  test 'consumables and products without an entitlement key grant nothing' do
    coins = iap_product(product_id: 'example.coins', kind: 'consumable', entitlement: 'pro')
    txn(iap_product: coins, product_id: coins.product_id, expires_at: nil)
    EntitlementResolver.refresh(@user)
    assert_nil entitlement_for(@user)
  end

  test 'nil user is a no-op' do
    assert_equal [], EntitlementResolver.refresh(nil)
  end
end
