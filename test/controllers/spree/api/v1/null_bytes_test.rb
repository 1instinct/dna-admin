require 'test_helper'

# Postgres refuses NUL in text, and Rails raises ArgumentError building the query. Lookups treat
# it as not found and writes as a validation error, never a 500.
class Spree::Api::V1::NullBytesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @headers = auth(@user)
    create(:user_profile, user: @user, handle: 'nul_owner')
    create(:user_profile, handle: 'nul_target')
  end

  test 'GET a profile is 404' do
    get '/api/v1/profiles/abc%00def'
    assert_response :not_found
  end

  test 'follow and unfollow are 404' do
    post '/api/v1/profiles/abc%00def/follow', headers: @headers
    assert_response :not_found
    delete '/api/v1/profiles/abc%00def/follow', headers: @headers
    assert_response :not_found
  end

  test 'block and unblock are 404' do
    post '/api/v1/blocks', params: { handle: "abc\u0000def" }, headers: @headers
    assert_response :not_found
    delete '/api/v1/blocks/abc%00def', headers: @headers
    assert_response :not_found
  end

  test 'a report about such a handle is 404' do
    post '/api/v1/reports', params: { target: { type: 'profile', handle: "abc\u0000def" }, reason: 'spam' }, headers: @headers
    assert_response :not_found
  end

  test 'a report with NUL in details is 422' do
    post '/api/v1/reports', params: { target: { type: 'profile', handle: 'nul_target' }, reason: 'spam', details: "x\u0000y" },
                            headers: @headers
    assert_response :unprocessable_entity
    assert json['fields']['details'].present?
  end

  test 'handle_available calls it invalid' do
    get '/api/v1/profiles/handle_available', params: { handle: "abc\u0000def" }, headers: @headers
    assert_response :success
    assert_equal({ 'available' => false, 'reason' => 'invalid' }, json)
  end

  test 'PATCH with NUL in a field is 422 naming the field' do
    { handle: 'abc', name: 'x', bio: 'x', website: 'https://x.example/' }.each do |field, value|
      patch '/api/v1/profile', params: { profile: { field => "#{value}\u0000def" } }, headers: @headers
      assert_response :unprocessable_entity, field.to_s
      assert json['fields'][field.to_s].present?, field.to_s
    end
    assert_nil Spree::UserProfile.find_by(user_id: @user.id).bio
  end

  test 'NUL in a link value is invalid, not a database error' do
    profile = build(:user_profile, handle: 'nul_links', links: { 'instagram' => "a\u0000b" })
    refute profile.valid?
    assert profile.errors[:links].present?
  end
end
