require 'test_helper'

# A moderation lock holds on every way into the API, and unlocking restores access.
class Spree::Api::V1::LockedAccountTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, password: 'password123')
    @other = create(:user)
  end

  def sign_in_request
    post '/api/v1/users/sign_in.json', params: { user: { email: @user.email, password: 'password123' } }
  end

  test 'legacy sign_in refuses a locked user and does not issue an api key' do
    Profiles::Moderation.lock(@user)

    sign_in_request

    assert_equal 403, json['response_code'], 'legacy envelope: the code is in the body'
    assert_nil @user.reload.spree_api_key
    refute_includes response.body, 'spree_api_key'
  end

  test 'legacy sign_in with a wrong password does not reveal the lock' do
    Profiles::Moderation.lock(@user)

    post '/api/v1/users/sign_in.json', params: { user: { email: @user.email, password: 'wrong-password' } }

    assert_equal 401, json['response_code']
  end

  test 'an api key still on a locked account is refused' do
    @user.generate_spree_api_key!
    key = @user.spree_api_key
    @user.update_columns(locked_at: Time.current)

    post "/api/v1/users/#{@other.id}/follow.json", params: { token: key }

    assert_equal 401, response.status
    assert_equal 0, UserFollow.where(follower_id: @user.id).count
  end

  test 'a bearer token still on a locked account is refused' do
    token = token_for(@user)
    @user.update_columns(locked_at: Time.current)

    get '/api/v1/profile.json', headers: bearer(token)
    assert_equal 401, response.status

    post "/api/v1/users/#{@other.id}/follow.json", headers: bearer(token)
    assert_equal 401, response.status
    assert_equal 0, UserFollow.where(follower_id: @user.id).count
  end

  test 'a locked viewer is treated as a bad credential on the public profile' do
    create(:user_profile, user: @other, handle: 'target_one')
    token = token_for(@user)
    @user.update_columns(locked_at: Time.current)

    get '/api/v1/profiles/target_one.json', headers: bearer(token)

    assert_equal 401, response.status
  end

  test 'unlocking restores sign_in, api key and bearer access' do
    token = token_for(@user)
    @user.update_columns(locked_at: Time.current)
    get '/api/v1/profile.json', headers: bearer(token)
    assert_equal 401, response.status

    Profiles::Moderation.unlock(@user)

    get '/api/v1/profile.json', headers: bearer(token)
    assert_equal 200, response.status

    sign_in_request
    assert_equal 200, json['response_code']
    key = @user.reload.spree_api_key
    assert key.present?

    post "/api/v1/users/#{@other.id}/follow.json", params: { token: key }
    assert_equal 200, json['response_code']
    assert_equal 1, UserFollow.where(follower_id: @user.id).count
  end
end
