require 'test_helper'

class Reviews::StatsPointsTest < ActiveSupport::TestCase
  setup do
    reviews_enable!(photos_require_approval: false)
    @product = media_product(name: 'Wrap Top')
  end

  def review_from(user, **params)
    reviews_order(@product, user: user)
    reviews_submit(@product, user: user, **params).review
  end

  test 'stats per scope: a wholesale review never moves retail numbers' do
    review_from(create(:user), rating: 5, body: 'Love it')
    review_from(create(:user), rating: 4)
    review_from(reviews_wholesale_user, rating: 1, body: 'MOQ too high')

    retail = Spree::ReviewStat.for(@product, 'retail')
    assert_equal 4.5, retail.average.to_f
    assert_equal 2, retail.ratings_count
    assert_equal 1, retail.reviews_count, 'star-only ratings count as ratings, not written reviews'
    assert_equal({ 1 => 0, 2 => 0, 3 => 0, 4 => 1, 5 => 1 }, retail.histogram_counts)

    assert_equal 1.0, Spree::ReviewStat.for(@product, 'wholesale').average.to_f
    all = Spree::ReviewStat.for(@product, 'all')
    assert_equal 3.33, all.average.to_f
    assert_equal 3, all.ratings_count

    @product.reload
    assert_equal [4.5, 2], [@product.avg_rating.to_f, @product.reviews_count]
    assert_equal [3.33, 3], [@product.all_avg_rating.to_f, @product.all_reviews_count]
  end

  test 'attribute averages and photo counts' do
    create(:review_attribute, :fit)
    review_from(create(:user), rating: 5, attribute_ratings: { 'fit' => 2 }, photos: [reviews_photo])
    review_from(create(:user), rating: 4, attribute_ratings: { 'fit' => 3 })
    stat = Spree::ReviewStat.for(@product, 'retail')
    assert_equal({ 'fit' => { 'average' => 2.5, 'count' => 2 } }, stat.attribute_averages)
    assert_equal 1, stat.photos_count
  end

  test 'rejecting and hiding take a review out of the stats; changing channel moves it' do
    admin = media_admin
    review = review_from(create(:user), rating: 2)
    Reviews::Moderation.hide!(review, by: admin)
    assert_equal 0, @product.reload.reviews_count
    Reviews::Moderation.publish!(review, by: admin)
    assert_equal 1, @product.reload.reviews_count
    Reviews::Moderation.change_channel!(review, channel: 'wholesale', by: admin)
    assert_equal [0, 1], [@product.reload.reviews_count, @product.all_reviews_count]
    Reviews::Moderation.reject!(review, reason: 'spam', by: admin)
    assert_equal 0, @product.reload.all_reviews_count
  end

  test 'points: 50 for a review, whatever the rating, paid once' do
    low_user = create(:user)
    high_user = create(:user)
    low = review_from(low_user, rating: 1)
    review_from(high_user, rating: 5)
    assert_equal [50, 50], [low_user.reload.loyalty_points_balance, high_user.reload.loyalty_points_balance]
    assert low.incentivized

    Reviews::Moderation.hide!(low, by: media_admin)
    Reviews::Moderation.publish!(low, by: media_admin)
    assert_equal 50, low_user.reload.loyalty_points_balance, 'publishing again pays nothing more'
    assert_equal 1, low.loyalty_points_credit_transactions.count
  end

  test 'points: +50 with a photo' do
    user = create(:user)
    review_from(user, rating: 4, photos: [reviews_photo])
    assert_equal 100, user.reload.loyalty_points_balance
  end

  test 'points: none while a review waits, paid when it is approved' do
    reviews_enable!(auto_publish: false)
    user = create(:user)
    review = review_from(user, rating: 3)
    assert_equal 0, user.reload.loyalty_points_balance
    Reviews::Moderation.publish!(review, by: media_admin)
    assert_equal 50, user.reload.loyalty_points_balance
  end

  test 'points: none for a rejected review' do
    reviews_enable!(auto_publish: false)
    user = create(:user)
    review = review_from(user, rating: 3)
    Reviews::Moderation.reject!(review, reason: 'off_topic', by: media_admin)
    assert_equal 0, user.reload.loyalty_points_balance
  end

  test 'votes: one per voter, changeable, counted on the review' do
    review = review_from(create(:user), rating: 4, body: 'Helpful detail')
    voter = create(:user)
    Reviews::Votes.cast(review, helpful: true, user: voter)
    Reviews::Votes.cast(review, helpful: true, user: voter)
    Reviews::Votes.cast(review, helpful: true, visitor_id: 'abc')
    assert_equal [2, 0], [review.reload.helpful_count, review.unhelpful_count]
    Reviews::Votes.cast(review, helpful: false, user: voter)
    assert_equal [1, 1], [review.reload.helpful_count, review.unhelpful_count]
  end
end
