require 'test_helper'

class Reviews::SubmitTest < ActiveSupport::TestCase
  setup do
    reviews_enable!
    @product = media_product(name: 'Wrap Top')
  end

  def buyer
    user = create(:user)
    reviews_order(@product, user: user)
    user
  end

  # Regression guard for FTC 16 CFR 465.7: moderation must never depend on the rating.
  test 'a 1-star and a 5-star review with the same text get the same status' do
    [
      'Soft fabric, runs small.',
      'Visit www.example-deals.com for more',
      'Call me on 555 010 0199 9'
    ].each do |text|
      low = reviews_submit(@product, user: buyer, rating: 1, body: text).review
      high = reviews_submit(@product, user: buyer, rating: 5, body: text).review
      assert_equal high.status, low.status, "different outcome for #{text.inspect}"
      assert_equal high.moderation_reason.to_s, low.moderation_reason.to_s
    end
  end

  test 'a clean review publishes straight away and counts in the stats' do
    review = reviews_submit(@product, user: buyer, rating: 2, title: 'Not for me', body: 'Sizing was off.').review
    assert_equal 'published', review.status
    assert review.published_at
    assert_equal 2.0, @product.reload.avg_rating.to_f
    assert_equal 1, @product.reviews_count
  end

  test 'links and contact details are held for a person to check' do
    review = reviews_submit(@product, user: buyer, rating: 5, body: 'Great, see https://spam.example').review
    assert_equal %w[pending auto_flag], [review.status, review.moderation_reason]
    assert_equal 0, @product.reload.reviews_count
  end

  test 'blocked terms are held' do
    with_moderation_lists(blocked: ['badword']) do
      review = reviews_submit(@product, user: buyer, rating: 5, body: 'what a badword top').review
      assert_equal 'pending', review.status
    end
  end

  test 'photos wait for approval when the setting is on' do
    review = reviews_submit(@product, user: buyer, rating: 5, photos: [reviews_photo]).review
    assert_equal %w[pending photos], [review.status, review.moderation_reason]
    assert_equal 1, review.photos.count

    reviews_enable!(photos_require_approval: false)
    review = reviews_submit(@product, user: buyer, rating: 5, photos: [reviews_photo]).review
    assert_equal 'published', review.status
  end

  test 'with auto-publish off every review waits' do
    reviews_enable!(auto_publish: false)
    review = reviews_submit(@product, user: buyer, rating: 5).review
    assert_equal %w[pending manual], [review.status, review.moderation_reason]
  end

  test 'someone who did not buy it cannot review it' do
    error = assert_raises(Reviews::Error) { reviews_submit(@product, user: create(:user), rating: 5) }
    assert_equal :not_eligible, error.code
  end

  test 'nothing is accepted while reviews are switched off' do
    reviews_enable!(enabled: false)
    error = assert_raises(Reviews::Error) { reviews_submit(@product, user: buyer, rating: 5) }
    assert_equal :not_enabled, error.code
  end

  test 'staff accounts cannot review' do
    error = assert_raises(Reviews::Error) { reviews_submit(@product, user: media_admin, rating: 5) }
    assert_equal :forbidden, error.code
  end

  test 'submitting again edits the review and moderates it again' do
    user = buyer
    first = reviews_submit(@product, user: user, rating: 5, body: 'Love it').review
    assert_nil first.edited_at
    edited = reviews_submit(@product, user: user, rating: 3, body: 'Pilled after a month, www.x.com').review
    assert_equal first.id, edited.id
    assert_equal 1, Spree::Review.count
    assert edited.edited_at
    assert_equal 'pending', edited.status
    assert_equal 0, @product.reload.reviews_count, 'the held edit leaves the stats'
  end

  test 'editing a review an admin rejected or hid sends it to a person, not to the page' do
    %i[reject! hide!].each do |action|
      user = buyer
      review = reviews_submit(@product, user: user, rating: 4, body: 'Fine').review
      args = action == :reject! ? { reason: 'off_topic', by: media_admin } : { by: media_admin }
      Reviews::Moderation.public_send(action, review, **args)
      edited = reviews_submit(@product, user: user, rating: 4, body: 'Fine, edited').review
      assert_equal %w[pending manual], [edited.status, edited.moderation_reason], action.to_s
    end
  end

  test 'invalid input comes back as errors on the review' do
    result = reviews_submit(@product, user: buyer, rating: 9)
    refute result.success?
    assert result.review.errors[:rating].any?
  end

  test 'records the purchase: order, line item, variant, verified and channel' do
    user = create(:user)
    order = reviews_order(@product, user: user)
    review = reviews_submit(@product, user: user, rating: 4).review
    assert_equal order.id, review.order_id
    assert_equal order.line_items.first.id, review.line_item_id
    assert_equal @product.master.id, review.variant_id
    assert review.verified_purchase
    assert_equal 'retail', review.channel
    assert_equal 'Maya R.', review.display_name
  end

  test 'a wholesale purchase gives a wholesale review' do
    user = reviews_wholesale_user
    reviews_order(@product, user: user)
    assert_equal 'wholesale', reviews_submit(@product, user: user, rating: 4).review.channel

    guest_trade = reviews_order(@product, channel: 'wholesale')
    request = Spree::ReviewRequest.create!(order: guest_trade, email: guest_trade.email, status: 'sent',
                                           send_after: Time.current)
    assert_equal 'wholesale', reviews_submit(@product, review_request: request, rating: 4).review.channel
  end

  test 'a guest reviews through the email link, without points' do
    order = reviews_order(@product)
    request = Spree::ReviewRequest.create!(order: order, email: order.email, status: 'sent', send_after: Time.current)
    review = reviews_submit(@product, review_request: request, rating: 5).review
    assert_equal 'published', review.status
    assert_equal 'email', review.source
    assert_nil review.user_id
    refute review.incentivized
  end

  test 'only the questions asked about this product are accepted' do
    create(:review_attribute, :fit)
    result = reviews_submit(@product, user: buyer, rating: 4, attribute_ratings: { 'fit' => '2' })
    assert_equal({ 'fit' => 2 }, result.review.attribute_ratings)
    assert_raises(Reviews::Error) { reviews_submit(@product, user: buyer, rating: 4, attribute_ratings: { 'smell' => 3 }) }
  end

  test 'store reviews need a shipped order' do
    store = media_store
    assert_raises(Reviews::Error) { reviews_submit(store, user: create(:user), rating: 5) }
    review = reviews_submit(store, user: buyer, rating: 4, body: 'Fast shipping').review
    assert_equal 'published', review.status
    refute review.incentivized, 'store reviews earn no points'
  end
end
