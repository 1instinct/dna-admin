require 'test_helper'

class Spree::ReviewTest < ActiveSupport::TestCase
  setup do
    @product = media_product(name: 'Rib-Knit Wrap Top')
  end

  def review(**attrs)
    Spree::Review.new({ reviewable: @product, rating: 5, display_name: 'Maya R.' }.merge(attrs))
  end

  test 'a rating alone is a valid review' do
    assert review.valid?, review.errors.full_messages.inspect
    refute review.written?
  end

  test 'rating must be a whole number from 1 to 5' do
    [0, 6, nil].each { |rating| refute review(rating: rating).valid?, "rating #{rating.inspect} was accepted" }
    (1..5).each { |rating| assert review(rating: rating).valid? }
  end

  test 'the database refuses out-of-range ratings too' do
    record = review
    record.save!
    assert_raises(ActiveRecord::StatementInvalid) { record.update_column(:rating, 9) }
  end

  test 'title and body lengths are limited' do
    refute review(title: 'x' * 121).valid?
    refute review(body: 'x' * 5001).valid?
    assert review(title: 'x' * 120, body: 'x' * 5000).valid?
  end

  test 'attribute ratings map known-shaped keys to 1-5' do
    assert review(attribute_ratings: { 'fit' => 2, 'quality' => 5 }).valid?
    refute review(attribute_ratings: { 'fit' => 6 }).valid?
    refute review(attribute_ratings: { 'Bad Key!' => 3 }).valid?
    refute review(attribute_ratings: { 'fit' => '3' }).valid?
  end

  test 'only products and the store can be reviewed' do
    refute Spree::Review.new(reviewable: create(:user), rating: 5, display_name: 'X').valid?
    assert Spree::Review.new(reviewable: media_store, rating: 5, display_name: 'X').valid?
  end

  test 'a rejection needs a reason from the fixed list' do
    refute review(status: 'rejected').valid?
    refute review(status: 'rejected', moderation_reason: 'too_negative').valid?
    assert review(status: 'rejected', moderation_reason: 'spam').valid?
  end

  test 'one review per product per user and per order' do
    user = create(:user)
    order = reviews_order(@product, user: user)
    review(user: user, order: order).save!
    refute review(user: user).valid?
    refute review(order: order).valid?
    assert review(user: create(:user)).valid?
  end

  test 'photos: at most five images of an allowed type' do
    record = review
    6.times { |i| record.photos.attach(reviews_photo("p#{i}.png")) }
    refute record.valid?
    assert_includes record.errors[:photos], "can't be more than 5"

    record = review
    record.photos.attach(io: StringIO.new('%PDF'), filename: 'doc.pdf', content_type: 'application/pdf')
    refute record.valid?
  end

  test 'default display name is first name and last initial from the order' do
    order = reviews_order(@product)
    assert_equal 'Maya R.', Spree::Review.default_display_name(order: order)
    assert_equal 'Customer', Spree::Review.default_display_name
  end

  test 'in_scope: retail by default, all, or wholesale' do
    retail = review.tap(&:save!)
    wholesale = review(channel: 'wholesale', user: create(:user)).tap(&:save!)
    assert_equal [retail], Spree::Review.in_scope('retail').to_a
    assert_equal [retail], Spree::Review.in_scope('anything').to_a
    assert_equal [wholesale], Spree::Review.in_scope('wholesale').to_a
    assert_equal [retail, wholesale].map(&:id).sort, Spree::Review.in_scope('all').pluck(:id).sort
  end
end
