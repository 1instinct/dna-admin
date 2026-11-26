require 'test_helper'

# The "Reviews" tab on a product: stats per channel, the AI summary preview and its Hide/Show
# switch, and the product's reviews. Admins only.
class Spree::Admin::ProductReviewsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    reviews_enable!(photos_require_approval: false)
    @product = media_product(name: 'Wrap Top')
    @admin = media_admin
    @base = "/admin/products/#{@product.slug}/reviews"
  end

  teardown { Warden.test_reset! }

  def review_from(user, **params)
    reviews_order(@product, user: user)
    reviews_submit(@product, user: user, **params).review
  end

  def listed
    response.body.scan(/id="product_review_(\d+)"/).flatten.map(&:to_i).sort
  end

  def add_summary(hidden: false)
    stat = Spree::ReviewStat.for(@product, 'retail')
    stat.update!(ai_summary: { 'headline' => 'Soft fabric, runs small',
                               'summary' => 'Most buyers like the fabric; several say to size up.',
                               'pros' => [{ 'label' => 'Soft fabric', 'mentions' => 12 }],
                               'cons' => [{ 'label' => 'Runs small', 'mentions' => 4 }] },
                 ai_summary_review_count: 16, ai_summary_generated_at: Time.zone.parse('2026-11-20 10:00'),
                 ai_summary_hidden: hidden)
    stat
  end

  def with_captured_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  test 'admin only' do
    stat = add_summary
    get @base
    refute_includes response.body, 'Soft fabric', 'anonymous gets the login page'

    login_as(create(:user), scope: :spree_user)
    get @base
    assert_response :redirect
    refute_includes response.body, 'Soft fabric'
    post "#{@base}/toggle_ai_summary"
    refute stat.reload.ai_summary_hidden
  end

  test 'the product edit page links to the Reviews tab' do
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{@product.slug}/edit"
    assert_response :success
    assert_includes response.body, %(href="http://www.example.com#{@base}")
  end

  test 'retail by default: stats, histogram and the retail reviews, each linking to the queue' do
    loved = review_from(create(:user), rating: 5, body: 'Lovely soft fabric')
    star_only = review_from(create(:user), rating: 4)
    wholesale = review_from(reviews_wholesale_user, rating: 1, body: 'MOQ too high')
    waiting = review_from(create(:user), rating: 2, body: 'Seams came loose')
    Reviews::Moderation.hold!(waiting, 'manual')

    login_as(@admin, scope: :spree_user)
    get @base
    assert_response :success
    assert_select '#product_review_scope_retail.active'
    assert_select '#product_review_average', '4.50'
    assert_select '#product_review_ratings_count', '2'
    assert_select '#product_review_written_count', '1'
    assert_select '#product_review_pending_count', '1'
    assert_select '#product_review_histogram_5', /1 \(50%\)/
    assert_select '#product_review_histogram_1', /0 \(0%\)/
    assert_equal [loved.id, star_only.id, waiting.id].sort, listed, 'every status, retail only'
    assert_includes response.body, %(href="/admin/reviews/#{loved.id}")
    assert_select "#product_review_#{star_only.id}", /Rating only/
    assert_select "#product_review_#{waiting.id} .badge", 'Waiting'
    refute_includes listed, wholesale.id
  end

  test 'wholesale and all-channel scopes' do
    retail = review_from(create(:user), rating: 5, body: 'Great')
    wholesale = review_from(reviews_wholesale_user, rating: 1, body: 'MOQ too high')
    login_as(@admin, scope: :spree_user)

    get @base, params: { scope: 'wholesale' }
    assert_select '#product_review_scope_wholesale.active'
    assert_select '#product_review_average', '1.00'
    assert_equal [wholesale.id], listed
    assert_select "#product_review_#{wholesale.id}", /Wholesale/

    get @base, params: { scope: 'all' }
    assert_select '#product_review_average', '3.00'
    assert_select '#product_review_ratings_count', '2'
    assert_equal [retail.id, wholesale.id].sort, listed

    get @base, params: { scope: 'bogus' }
    assert_select '#product_review_scope_retail.active'
    assert_equal [retail.id], listed
  end

  test 'question averages use the question labels' do
    create(:review_attribute, :fit)
    review_from(create(:user), rating: 5, attribute_ratings: { 'fit' => 1 })
    review_from(create(:user), rating: 4, attribute_ratings: { 'fit' => 2 })
    login_as(@admin, scope: :spree_user)
    get @base
    assert_select '#product_review_attribute_fit', /Fit/
    assert_select '#product_review_attribute_fit', /1\.50/
    assert_select '#product_review_attribute_fit', /Leans “Runs small”/
  end

  test 'empty product: no reviews, no summary, Regenerate disabled' do
    login_as(@admin, scope: :spree_user)
    get @base
    assert_response :success
    assert_includes response.body, 'No published reviews in this channel yet.'
    assert_select '#ai_summary_empty'
    assert_select '#regenerate_ai_summary[disabled]'
    assert_select '#toggle_ai_summary', count: 0
    assert_includes response.body, 'milestone M7'
  end

  test 'AI summary preview, then hide and show again (logged)' do
    stat = add_summary
    login_as(@admin, scope: :spree_user)
    get @base, params: { scope: 'wholesale' }
    assert_select '#ai_summary_headline', 'Soft fabric, runs small'
    assert_select '#ai_summary_pros', /Soft fabric\s*\(12 mentions\)/
    assert_select '#ai_summary_cons', /Runs small\s*\(4 mentions\)/
    assert_select '#ai_summary_meta', /16 retail reviews/
    assert_select '#ai_summary_state', 'Shown on the product page'

    log = with_captured_log { post "#{@base}/toggle_ai_summary", params: { scope: 'wholesale' } }
    assert_redirected_to "#{@base}?scope=wholesale"
    assert stat.reload.ai_summary_hidden
    assert_match(/AI summary hidden for product #{@product.id} by admin user #{@admin.id} at /, log)
    assert_nil Reviews::Presenter.new.summary(@product, 'retail')[:ai_summary], 'hidden from the storefront'

    follow_redirect!
    assert_select '#ai_summary_state', 'Hidden from the product page'
    assert_select '#toggle_ai_summary[value=?]', 'Show on product page'

    log = with_captured_log { post "#{@base}/toggle_ai_summary" }
    assert_redirected_to @base
    refute stat.reload.ai_summary_hidden
    assert_match(/AI summary shown for product #{@product.id}/, log)
  end

  test 'toggling with no summary does nothing' do
    login_as(@admin, scope: :spree_user)
    assert_no_difference -> { Spree::ReviewStat.count } do
      post "#{@base}/toggle_ai_summary"
    end
    assert_redirected_to @base
    assert_equal 'This product has no AI summary yet.', flash[:error]
  end
end
