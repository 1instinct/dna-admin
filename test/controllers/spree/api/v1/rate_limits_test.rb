require 'test_helper'
require 'minitest/mock'

# Follow, block, handle_available and avatar uploads answer 429 past their per-user limit.
class Spree::Api::V1::RateLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @headers = auth(@user)
    @target = create(:user_profile, handle: 'target_one')
    @second = create(:user_profile, handle: 'target_two')
    Profiles.config.rate_limits.each_key { |action| Profiles.config.rate_limits[action] = { limit: 1, window: 1.hour } }
  end

  teardown { Profiles.reset_config! }

  def assert_limited
    assert_response :too_many_requests
    assert json['error'].present?
  end

  test 'follow and unfollow share a limit' do
    post '/api/v1/profiles/target_one/follow', headers: @headers
    assert_response :success

    delete '/api/v1/profiles/target_one/follow', headers: @headers
    assert_limited
    assert UserFollow.where(follower_id: @user.id, following_id: @target.user_id).exists?
  end

  test 'block and unblock share a limit' do
    post '/api/v1/blocks', params: { handle: 'target_one' }, headers: @headers
    assert_response :created

    post '/api/v1/blocks', params: { handle: 'target_two' }, headers: @headers
    assert_limited
    refute Spree::UserBlock.between?(@user, @second.user)

    delete '/api/v1/blocks/target_one', headers: @headers
    assert_limited
  end

  test 'handle_available' do
    get '/api/v1/profiles/handle_available', params: { handle: 'free_one' }, headers: @headers
    assert_response :success

    get '/api/v1/profiles/handle_available', params: { handle: 'free_two' }, headers: @headers
    assert_limited
  end

  test 'avatar upload counts attempts, including refused ones' do
    put '/api/v1/profile/avatar', params: { avatar: 'not a file' }, headers: @headers
    assert_response :unprocessable_entity

    put '/api/v1/profile/avatar', params: { avatar: fixture_upload('avatar.png', 'image/png') }, headers: @headers
    assert_limited
    refute Spree::UserProfile.find_by(user_id: @user.id)&.avatar&.attached?
  end

  test 'legacy follow and unfollow use the follow limit, in the legacy envelope' do
    post "/api/v1/users/#{@target.user_id}/follow.json", headers: @headers
    assert_equal 200, json['response_code']

    post "/api/v1/users/#{@second.user_id}/follow.json", headers: @headers
    assert_equal 429, json['response_code']
    assert_equal 1, UserFollow.where(follower_id: @user.id).count

    post "/api/v1/users/#{@target.user_id}/unfollow.json", headers: @headers
    assert_equal 429, json['response_code']
  end

  test 'one user at the limit does not affect another' do
    post '/api/v1/profiles/target_one/follow', headers: @headers
    post '/api/v1/profiles/target_one/follow', headers: auth(create(:user))
    assert_response :success
  end

  # A limiter fault must never take the action down with it.
  def with_broken_counter
    Profiles::RateLimit.stub(:hit, ->(*) { raise ActiveRecord::StatementInvalid, 'PG::Error for user 42' }) { yield }
  end

  test 'a counter error fails open on every caller' do
    with_broken_counter do
      post '/api/v1/profiles/target_one/follow', headers: @headers
      assert_response :success
      assert UserFollow.where(follower_id: @user.id, following_id: @target.user_id).exists?

      delete '/api/v1/profiles/target_one/follow', headers: @headers
      assert_response :success

      get '/api/v1/profiles/handle_available', params: { handle: 'free_one' }, headers: @headers
      assert_response :success

      post '/api/v1/blocks', params: { handle: 'target_two' }, headers: @headers
      assert_response :created

      delete '/api/v1/blocks/target_two', headers: @headers
      assert_response :no_content

      put '/api/v1/profile/avatar', params: { avatar: fixture_upload('avatar.png', 'image/png') }, headers: @headers
      assert_response :success

      post "/api/v1/users/#{@target.user_id}/follow.json", headers: @headers
      assert_equal 200, json['response_code']

      post "/api/v1/users/#{@target.user_id}/unfollow.json", headers: @headers
      assert_equal 200, json['response_code']
    end
  end

  test 'a counter error logs the class only' do
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    with_broken_counter { assert Profiles::RateLimit.allow?(@user, :follow) }

    assert_includes io.string, 'ActiveRecord::StatementInvalid'
    refute_includes io.string, 'user 42'
  ensure
    Rails.logger = old_logger
  end

  test 'an unsaved user is never counted' do
    assert Profiles::RateLimit.allow?(Spree::User.new, :follow)
    assert Profiles::RateLimit.allow?(nil, :follow)
    assert_equal 0, Spree::ProfileRateCounter.count
  end

  test 'a guest with an order token cannot use legacy follow or unfollow, and gets no 500' do
    store = Spree::Store.default
    unless store.persisted?
      store = Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: 'rate-test',
                                   mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
    end
    order = Spree::Order.create!(email: 'guest@example.com', store: store, currency: 'USD')
    assert order.token.present?
    params = { order_token: order.token, order_id: order.number }

    post "/api/v1/users/#{@target.user_id}/follow.json", params: params
    assert_equal 401, json['response_code']

    post "/api/v1/users/#{@target.user_id}/unfollow.json", params: params
    assert_equal 401, json['response_code']

    assert_equal 0, UserFollow.count
    assert_equal 0, Spree::ProfileRateCounter.count
  end

  test 'requests without a bearer are 401 and not counted' do
    get '/api/v1/profiles/handle_available', params: { handle: 'free_one' }
    assert_response :unauthorized
    assert_equal 0, Spree::ProfileRateCounter.count
  end
end
