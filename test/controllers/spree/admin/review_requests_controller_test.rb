require 'test_helper'

# Reviews > Review emails: the request list, status filter and 30-day funnel.
class Spree::Admin::ReviewRequestsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    reviews_enable!
    product = media_product(name: 'Wrap Top')
    @sent, = review_request_for(reviews_order(product, email: 'sent@example.com'), sent_at: 2.days.ago)
    @opened, = review_request_for(reviews_order(product, email: 'opened@example.com'), sent_at: 3.days.ago,
                                                                                         opened_at: 2.days.ago)
    @done, = review_request_for(reviews_order(product, email: 'done@example.com'), status: 'completed',
                                                                                     sent_at: 5.days.ago, opened_at: 4.days.ago,
                                                                                     completed_at: 4.days.ago)
    @waiting, = review_request_for(reviews_order(product, email: 'waiting@example.com'), status: 'scheduled',
                                                                                           send_after: 3.days.from_now)
    login_as(media_admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'lists requests with their order and the funnel' do
    get '/admin/review_requests'
    assert_response :success
    [@sent, @opened, @done, @waiting].each do |request|
      assert_includes response.body, request.email
      assert_includes response.body, request.order.number
    end
    funnel = response.body[%r{<p class="mb-3" id="review_requests_funnel">(.*?)</p>}m, 1].squish
    assert_equal 'Last 30 days: <strong>3</strong> sent → <strong>2</strong> opened (67%) → <strong>1</strong> completed (33%)', funnel
    assert_select 'a[href="/admin/review_requests"]', minimum: 1 # the menu tab
  end

  test 'filters by status' do
    get '/admin/review_requests', params: { status: 'scheduled' }
    assert_response :success
    assert_includes response.body, 'waiting@example.com'
    refute_includes response.body, 'sent@example.com'
  end

  test 'admins only' do
    Warden.test_reset!
    login_as(create(:user), scope: :spree_user)
    get '/admin/review_requests'
    assert_response :redirect
  end
end
