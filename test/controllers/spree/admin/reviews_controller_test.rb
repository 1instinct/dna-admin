require 'test_helper'

# Reviews > Reviews: the moderation queue and a review's page.
class Spree::Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    reviews_enable!(photos_require_approval: true)
    @admin = media_admin
    @product = media_product(name: 'Wrap Top')
    @published = review_by(rating: 5, title: 'Lovely', body: 'Soft and warm')
    @held = review_by(rating: 1, body: 'Fell apart, see www.example.com')
    @with_photo = review_by(rating: 3, photos: [reviews_photo])
  end

  teardown { Warden.test_reset! }

  def review_by(**params)
    user = create(:user)
    reviews_order(@product, user: user)
    reviews_submit(@product, user: user, **params).review
  end

  test 'admin only' do
    get '/admin/reviews'
    refute_includes response.body, "review_#{@held.id}"
    login_as(create(:user), scope: :spree_user)
    get '/admin/reviews'
    refute_includes response.body, "review_#{@held.id}"
  end

  test 'the queue shows waiting reviews first, with why they wait' do
    login_as(@admin, scope: :spree_user)
    get '/admin/reviews'
    assert_response :success
    assert_includes response.body, "review_#{@held.id}"
    assert_includes response.body, "review_#{@with_photo.id}"
    refute_includes response.body, "review_#{@published.id}"
    assert_includes response.body, 'Has a link, contact details or a blocked word'
    assert_includes response.body, 'Photos waiting for approval'
    assert_includes response.body, 'never on its rating'
    assert_includes response.body, 'sidebarReviews'
  end

  test 'filters: status, rating, channel, photos, search' do
    login_as(@admin, scope: :spree_user)
    get '/admin/reviews', params: { status: 'all', rating: 5 }
    assert_includes response.body, "review_#{@published.id}"
    refute_includes response.body, "review_#{@held.id}"
    get '/admin/reviews', params: { status: 'all', photos: 'yes' }
    assert_includes response.body, "review_#{@with_photo.id}"
    refute_includes response.body, "review_#{@published.id}"
    get '/admin/reviews', params: { status: 'all', q: 'warm' }
    assert_includes response.body, "review_#{@published.id}"
    refute_includes response.body, "review_#{@held.id}"
    get '/admin/reviews', params: { status: 'all', channel: 'wholesale' }
    refute_includes response.body, "review_#{@published.id}"
  end

  test 'publish, hide and reject (reject needs a reason)' do
    login_as(@admin, scope: :spree_user)
    post "/admin/reviews/#{@with_photo.id}/publish"
    assert_equal 'published', @with_photo.reload.status
    assert_equal @admin, @with_photo.moderated_by
    assert_equal 2, @product.reload.reviews_count

    post "/admin/reviews/#{@held.id}/reject"
    assert_equal 'pending', @held.reload.status
    post "/admin/reviews/#{@held.id}/reject", params: { reason: 'spam' }
    assert_equal %w[rejected spam], [@held.reload.status, @held.moderation_reason]

    post "/admin/reviews/#{@published.id}/hide"
    assert_equal 'hidden', @published.reload.status
    assert_equal 1, @product.reload.reviews_count
  end

  test 'publishing a reported review closes its open reports' do
    Spree::ContentReport.for_review(@published, reporter: create(:user), reason: 'spam').save!
    Reviews::Reports.refresh_count(@published)
    login_as(@admin, scope: :spree_user)
    Reviews::Moderation.hold!(@published, 'reported')
    post "/admin/reviews/#{@published.id}/publish"
    assert_equal ['published', 0], [@published.reload.status, @published.reports_count]
    assert_equal ['dismissed'], Spree::ContentReport.about_review(@published).pluck(:status)
  end

  test 'the review page shows everything needed to decide, and saves a reply' do
    login_as(@admin, scope: :spree_user)
    get "/admin/reviews/#{@with_photo.id}"
    assert_response :success
    assert_includes response.body, 'Photos waiting for approval'
    assert_includes response.body, @with_photo.order.number
    assert_includes response.body, 'review_photos'

    post "/admin/reviews/#{@published.id}/reply", params: { reply_body: 'Thank you!' }
    @published.reload
    assert_equal ['Thank you!', @admin], [@published.reply_body, @published.reply_author]
    post "/admin/reviews/#{@published.id}/reply", params: { reply_body: '' }
    assert_nil @published.reload.reply_body
  end

  test 'moving a review between channels updates both stats' do
    login_as(@admin, scope: :spree_user)
    post "/admin/reviews/#{@published.id}/change_channel", params: { channel: 'wholesale' }
    assert_equal 'wholesale', @published.reload.channel
    assert_equal [0, 1], [@product.reload.reviews_count, @product.all_reviews_count]
  end

  test 'removing a photo' do
    login_as(@admin, scope: :spree_user)
    photo = @with_photo.photos.first
    delete "/admin/reviews/#{@with_photo.id}/photo", params: { photo_id: photo.id }
    refute @with_photo.reload.photos.attached?
    refute ActiveStorage::Blob.exists?(photo.blob_id)
  end

  test 'bulk publish, and bulk reject needs a reason' do
    login_as(@admin, scope: :spree_user)
    post '/admin/reviews/bulk', params: { bulk_action: 'reject', ids: [@held.id, @with_photo.id] }
    assert_equal %w[pending pending], [@held.reload.status, @with_photo.reload.status]
    post '/admin/reviews/bulk', params: { bulk_action: 'publish', ids: [@held.id, @with_photo.id] }
    assert_equal %w[published published], [@held.reload.status, @with_photo.reload.status]
    assert_equal 3, @product.reload.reviews_count
  end
end
