require 'test_helper'

# What deleting an account does to the customer's reviews, questions, votes and review emails.
class AccountDeletionReviewsTest < ActiveSupport::TestCase
  setup do
    reviews_enable!(photos_require_approval: false)
    @product = media_product(name: 'Wrap Top')
    @user = create(:user)
    @order = reviews_order(@product, user: @user)
    @review = reviews_submit(@product, user: @user, rating: 2, title: 'Runs small', body: 'Size up.',
                                       photos: [reviews_photo]).review
  end

  test 'reviews stay, anonymized, and the average does not move' do
    assert_equal 2.0, @product.reload.avg_rating.to_f
    blob = @review.photos.first.blob

    AccountDeletion.call(@user)

    @review.reload
    assert_nil @review.user_id
    assert_equal 'Former customer', @review.display_name
    assert_equal ['Runs small', 'Size up.', 2], [@review.title, @review.body, @review.rating]
    assert_equal 'published', @review.status
    refute @review.photos.attached?
    refute ActiveStorage::Blob.exists?(blob.id), 'photo purged'
    assert_equal [2.0, 1], [@product.reload.avg_rating.to_f, @product.reviews_count]
    assert_equal 0, Spree::ReviewStat.for(@product, 'retail').photos_count
  end

  test "the user's votes go and the counts follow" do
    other = create(:user)
    reviews_order(@product, user: other)
    other_review = reviews_submit(@product, user: other, rating: 5, body: 'Great').review
    Reviews::Votes.cast(other_review, helpful: true, user: @user)
    assert_equal 1, other_review.reload.helpful_count

    AccountDeletion.call(@user)

    assert_equal 0, other_review.reload.helpful_count
    assert_equal 0, Spree::ReviewVote.count
  end

  test 'questions and answers stay, anonymized' do
    question = Spree::ProductQuestion.create!(product: @product, user: @user, body: 'Does it stretch?',
                                              display_name: 'Maya R.', status: 'published')
    AccountDeletion.call(@user)
    question.reload
    assert_nil question.user_id
    assert_equal 'Former customer', question.display_name
  end

  test 'open review emails are cancelled and their address and link cleared' do
    request = Spree::ReviewRequest.create!(order: @order, user: @user, email: @user.email, status: 'scheduled',
                                           send_after: 1.day.from_now)
    request.issue_token!
    AccountDeletion.call(@user)
    request.reload
    assert_equal 'cancelled', request.status
    assert_equal 'deleted@invalid', request.email
    assert_nil request.token_digest
    assert_nil request.user_id
  end
end
