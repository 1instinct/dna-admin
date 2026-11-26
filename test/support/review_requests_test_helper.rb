# Shared setup for the review request email tests (M4): a request in a given state, with a live
# token when it has been sent.
module ReviewRequestsTestHelper
  # A store whose home country is `country`, so orders shipped there are domestic. Its own row:
  # Spree::Store.default is cached (in the test cache store too) and can point at a store another
  # test rolled back.
  def review_requests_home!(country = reviews_country)
    @review_requests_store = Spree::Store.create!(name: 'Test Store', url: 'reviews.example.com',
                                                  code: "rr-#{SecureRandom.hex(3)}", mail_from_address: 'store@example.com',
                                                  default_currency: 'USD', default_country: country)
    country
  end

  # reviews_order, placed in the store from review_requests_home!.
  def review_requests_order(*items, **options)
    order = reviews_order(*items, **options)
    order.update_columns(store_id: @review_requests_store.id) if @review_requests_store
    order.reload
  end

  # A request for `order`. Returns [request, raw token]; the token is nil while scheduled.
  def review_request_for(order, status: 'sent', send_after: 1.day.ago, expires_at: 30.days.from_now, **attrs)
    request = Spree::ReviewRequest.create!({ order: order, user: order.user, email: order.email, status: status,
                                             send_after: send_after, expires_at: expires_at }.merge(attrs))
    token = status == 'scheduled' ? nil : request.issue_token!
    [request, token]
  end
end

ActiveSupport::TestCase.include(ReviewRequestsTestHelper)
