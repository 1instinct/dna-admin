require "test_helper"

# The app registers its Expo push token with the user's OAuth token (Authorization: Bearer). The
# body's `token` param is the push token, never an api key.
class Spree::Api::V1::PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  PUSH_TOKEN = "ExponentPushToken[test-device]".freeze

  setup do
    @user = Spree.user_class.create!(email: "push#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "valid bearer token registers the device for its owner" do
    post "/api/v1/push_subscriptions.json", params: { token: PUSH_TOKEN, platform: "ios" }, headers: bearer(token_for(@user))
    assert_response :success
    subscription = PushSubscription.find_by(token: PUSH_TOKEN)
    assert_equal @user.id, subscription.user_id
    assert subscription.enabled
  end

  test "unknown bearer token is 401, not a server error" do
    post "/api/v1/push_subscriptions.json", params: { token: PUSH_TOKEN, platform: "ios" }, headers: bearer("not-a-real-token")
    assert_response :unauthorized
    assert_nil PushSubscription.find_by(token: PUSH_TOKEN)
  end

  test "revoked bearer token is 401" do
    token = token_for(@user)
    Doorkeeper.config.access_token_model.by_token(token).revoke
    post "/api/v1/push_subscriptions.json", params: { token: PUSH_TOKEN, platform: "ios" }, headers: bearer(token)
    assert_response :unauthorized
  end

  test "no credentials is 401" do
    post "/api/v1/push_subscriptions.json", params: { token: PUSH_TOKEN, platform: "ios" }
    assert_response :unauthorized
  end

  test "destroy removes only the bearer's own subscription" do
    PushSubscription.create!(token: PUSH_TOKEN, platform: "ios", user: @user, enabled: true)
    delete "/api/v1/push_subscriptions/#{CGI.escape(PUSH_TOKEN)}.json", headers: bearer(token_for(@user))
    assert_response :success
    assert_nil PushSubscription.find_by(token: PUSH_TOKEN)
  end

  private

  def token_for(user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: "")
    record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
