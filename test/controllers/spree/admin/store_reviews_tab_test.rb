require 'test_helper'

# Reviews > Store reviews (M5): the review queue, filtered to reviews of the store.
class Spree::Admin::StoreReviewsTabTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    reviews_enable!(store_reviews_enabled: true)
    @admin = media_admin
    @store = reviews_store
    @product = media_product(name: 'Wrap Top')
    user = create(:user)
    reviews_order(@product, user: user)
    @store_review = reviews_submit(@store, user: user, rating: 4, body: 'Well packed').review
    @product_review = reviews_submit(@product, user: user, rating: 5, body: 'Soft').review
  end

  teardown { Warden.test_reset! }

  test 'the Store reviews tab opens the queue filtered to the store' do
    login_as(@admin, scope: :spree_user)
    get '/admin/reviews'
    assert_includes response.body, 'sidebar_store_reviews'
    assert_includes response.body, '/admin/reviews?subject=store'

    get '/admin/reviews', params: { subject: 'store', status: 'all' }
    assert_response :success
    assert_includes response.body, "review_#{@store_review.id}"
    refute_includes response.body, "review_#{@product_review.id}"
    assert_includes response.body, 'Store reviews'
    assert_includes response.body, "The store (#{@store.name})"
    assert_match(/class="[^"]*selected[^"]*" id="sidebar_store_reviews"/, response.body)

    get "/admin/reviews/#{@store_review.id}"
    assert_response :success
    assert_includes response.body, "The store (#{@store.name})"
    assert_includes response.body, 'store reviews page'
  end
end
