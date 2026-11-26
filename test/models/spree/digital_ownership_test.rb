require 'test_helper'

class Spree::DigitalOwnershipTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @variant = create(:digital_product).master
  end

  test 'grant! twice returns the same active ownership' do
    first = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'grant')
    second = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'free')

    assert_equal first, second
    assert_equal 'grant', second.source
    assert first.granted_at.present?
    assert_equal 1, Spree::DigitalOwnership.count
  end

  test 'grant! records the source record' do
    order = Spree::Order.create!(user: @user, email: @user.email, store: digital_store, currency: 'USD')
    ownership = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'order', source_record: order)
    assert_equal order, ownership.source_record
    assert_equal 'Spree::Order', ownership.source_type
  end

  test 'grant! after revoke! creates a new active row' do
    first = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'grant')
    first.revoke!('admin_revoked')
    assert first.reload.revoked?
    assert_equal 'admin_revoked', first.revoke_reason

    second = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'grant')
    refute_equal first, second
    assert second.active?
    assert_equal [second], Spree::DigitalOwnership.active.to_a
  end

  test 'revoke! twice keeps the first reason and time' do
    ownership = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'grant')
    ownership.revoke!('first')
    at = ownership.revoked_at
    ownership.revoke!('second')
    assert_equal 'first', ownership.reload.revoke_reason
    assert_equal at.to_i, ownership.revoked_at.to_i
  end

  test 'unique active index rejects a duplicate insert' do
    create(:digital_ownership, user: @user, variant: @variant)
    duplicate = build(:digital_ownership, user: @user, variant: @variant)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test 'source must be one of order iap grant free' do
    refute build(:digital_ownership, source: 'gift').valid?
    %w[order iap grant free].each { |s| assert build(:digital_ownership, source: s).valid?, s }
  end
end
