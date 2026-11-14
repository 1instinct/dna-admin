require 'test_helper'

class Creators::ReviewerTest < ActiveSupport::TestCase
  setup do
    digital_store
    @marketplace, @packs = marketplace_taxons
    @admin = admin_user
    @creator = creator_user
    @product = creator_product(@creator, taxons: [@packs])
    @product.update!(review_state: 'submitted', submitted_at: Time.current)
  end

  test 'admin approve publishes and makes available' do
    Creators::Reviewer.approve!(@product, @admin, 'Great')

    @product.reload
    assert_equal 'approved', @product.review_state
    assert_equal 'Great', @product.review_note
    assert @product.available?
    assert_includes @product.taxons, @marketplace
    assert_includes @product.taxons, @packs
    asset = @product.master.live_digital_asset
    assert_equal 1, asset.version
    assert asset.published?
  end

  test 'approve keeps an existing available_on' do
    since = 3.days.ago.change(usec: 0)
    @product.update!(available_on: since)
    Creators::Reviewer.approve!(@product, @admin)
    assert_equal since, @product.reload.available_on
  end

  test 'approve without a marketplace taxon still publishes' do
    Creators.config.marketplace_taxon_permalink = 'missing'
    Creators::Reviewer.approve!(@product, @admin)
    assert @product.reload.available?
  ensure
    Creators.reset_config!
  end

  test 'request_changes stores note' do
    Creators::Reviewer.request_changes!(@product, @admin, 'Trim the tails')
    assert_equal 'changes_requested', @product.reload.review_state
    assert_equal 'Trim the tails', @product.review_note
    refute @product.available?
    assert_nil @product.master.live_digital_asset
  end

  test 'reject stores note' do
    Creators::Reviewer.reject!(@product, @admin, 'Not original')
    assert_equal 'rejected', @product.reload.review_state
    assert_equal 'Not original', @product.review_note
  end

  test 'only submitted products can be reviewed' do
    @product.update!(review_state: 'draft')
    assert_raises(Creators::Reviewer::Error) { Creators::Reviewer.approve!(@product, @admin) }
    assert_raises(Creators::Reviewer::Error) { Creators::Reviewer.reject!(@product, @admin, 'x') }
    assert_raises(Creators::Reviewer::Error) { Creators::Reviewer.request_changes!(@product, @admin, 'x') }
  end

  test 'rejecting or requesting changes needs a note' do
    assert_raises(Creators::Reviewer::Error) { Creators::Reviewer.reject!(@product, @admin, ' ') }
    assert_raises(Creators::Reviewer::Error) { Creators::Reviewer.request_changes!(@product, @admin, nil) }
    assert_equal 'submitted', @product.reload.review_state
  end
end
