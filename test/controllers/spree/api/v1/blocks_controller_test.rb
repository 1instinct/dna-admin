require 'test_helper'

# GET /api/v1/blocks, POST /api/v1/blocks { handle }, DELETE /api/v1/blocks/:handle. Bearer.
class Spree::Api::V1::BlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @me = create(:user)
    create(:user_profile, user: @me, handle: 'me_me')
    @them = create(:user, email: 'them-secret@example.com')
    create(:user_profile, user: @them, handle: 'them', name: 'Them')
    @headers = auth(@me)
  end

  test 'all block endpoints require a bearer' do
    get '/api/v1/blocks'
    assert_response :unauthorized
    post '/api/v1/blocks', params: { handle: 'them' }
    assert_response :unauthorized
    delete '/api/v1/blocks/them'
    assert_response :unauthorized
  end

  test 'create blocks by handle: 201, follows both ways removed' do
    UserFollow.create!(follower: @me, following: @them)
    UserFollow.create!(follower: @them, following: @me)

    post '/api/v1/blocks', params: { handle: 'THEM' }, headers: @headers, as: :json
    assert_response :created
    assert_equal({ 'handle' => 'them', 'name' => 'Them', 'avatar' => nil }, json)
    assert @me.blocking?(@them)
    assert_equal 0, UserFollow.count
  end

  test 'create is idempotent' do
    2.times do
      post '/api/v1/blocks', params: { handle: 'them' }, headers: @headers, as: :json
      assert_response :created
    end
    assert_equal 1, Spree::UserBlock.count
  end

  test 'create 404 for an unknown handle and 422 for yourself' do
    post '/api/v1/blocks', params: { handle: 'nobody' }, headers: @headers, as: :json
    assert_response :not_found
    post '/api/v1/blocks', params: { handle: 'me_me' }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test 'a hidden profile can still be blocked' do
    @them.profile.update_column(:hidden_at, Time.current)
    post '/api/v1/blocks', params: { handle: 'them' }, headers: @headers, as: :json
    assert_response :created
  end

  test 'index lists only my blocks as handle, name, avatar' do
    Spree::UserBlock.block!(@me, @them)
    other = create(:user)
    create(:user_profile, user: other, handle: 'other')
    Spree::UserBlock.block!(other, @me)

    get '/api/v1/blocks', headers: @headers
    assert_response :success
    assert_equal [{ 'handle' => 'them', 'name' => 'Them', 'avatar' => nil }], json
    refute_includes response.body, 'them-secret@example.com'
  end

  test 'destroy removes my block: 204' do
    Spree::UserBlock.block!(@me, @them)
    delete '/api/v1/blocks/them', headers: @headers
    assert_response :no_content
    refute @me.blocking?(@them)
  end

  test "destroy 404 when I have no such block; can't remove another user's block" do
    Spree::UserBlock.block!(@them, @me)
    delete '/api/v1/blocks/them', headers: @headers
    assert_response :not_found

    delete '/api/v1/blocks/me_me', headers: @headers
    assert_response :not_found
    assert @them.blocking?(@me), "the other user's block stays"
  end
end
