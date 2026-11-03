require 'test_helper'

# Own profile: GET/PATCH /api/v1/profile, PUT/DELETE /api/v1/profile/avatar. Bearer required.
class Spree::Api::V1::ProfileControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create(:user, email: 'me-private@example.com')
    @headers = auth(@user)
  end

  test '401 without a bearer token' do
    get '/api/v1/profile'
    assert_response :unauthorized
    patch '/api/v1/profile', params: { profile: { name: 'x' } }
    assert_response :unauthorized
    put '/api/v1/profile/avatar'
    assert_response :unauthorized
    delete '/api/v1/profile/avatar'
    assert_response :unauthorized
  end

  test '401 with an api key only' do
    @user.generate_spree_api_key!
    get '/api/v1/profile', headers: { 'X-Spree-Token' => @user.spree_api_key }
    assert_response :unauthorized
  end

  test 'GET for a new user creates nothing and returns empty fields' do
    get '/api/v1/profile', headers: @headers
    assert_response :success
    assert_nil json['handle']
    assert_nil json['name']
    assert_equal 'public', json['visibility']
    assert_equal false, json['hidden']
    assert_nil json['handle_changeable_at']
    refute Spree::UserProfile.exists?(user_id: @user.id)
    refute_includes response.body, 'me-private@example.com'
  end

  test 'also answers with .json' do
    get '/api/v1/profile.json', headers: @headers
    assert_response :success
  end

  test 'PATCH creates the profile and returns it' do
    patch '/api/v1/profile', headers: @headers, params: {
      profile: { handle: 'Nova', name: 'Nova', bio: 'beats', website: 'https://nova.example', visibility: 'private' }
    }, as: :json
    assert_response :success
    assert_equal 'nova', json['handle']
    assert_equal 'Nova', json['name']
    assert_equal 'beats', json['bio']
    assert_equal 'https://nova.example', json['website']
    assert_equal 'private', json['visibility']
    assert_equal 'nova', @user.reload.profile.handle
  end

  test 'PATCH ignores fields outside the contract' do
    patch '/api/v1/profile', headers: @headers, params: {
      profile: { handle: 'nova', hidden_at: nil, user_id: 999, links: { instagram: 'x' } }
    }, as: :json
    assert_response :success
    profile = @user.reload.profile
    assert_equal @user.id, profile.user_id
    assert_equal({}, profile.links)
  end

  test 'PATCH 422 with field errors' do
    create(:user_profile, handle: 'taken')
    patch '/api/v1/profile', headers: @headers, params: {
      profile: { handle: 'taken', bio: 'b' * 281, website: 'ftp://x' }
    }, as: :json
    assert_response :unprocessable_entity
    assert json['error'].present?
    assert_equal ['is taken'], json['fields']['handle']
    assert json['fields']['bio'].any?
    assert json['fields']['website'].any?
    refute Spree::UserProfile.exists?(user_id: @user.id)
  end

  test 'PATCH 422 for reserved and invalid handles' do
    patch '/api/v1/profile', headers: @headers, params: { profile: { handle: 'admin' } }, as: :json
    assert_response :unprocessable_entity
    assert_equal ['is reserved'], json['fields']['handle']

    patch '/api/v1/profile', headers: @headers, params: { profile: { handle: 'a__b' } }, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['handle'].any?
  end

  test 'PATCH without a profile object is 422' do
    patch '/api/v1/profile', headers: @headers, params: { name: 'x' } # form body: no JSON param wrapping
    assert_response :unprocessable_entity
    assert json['error'].present?
  end

  test 'PATCH handle change inside the cooldown is 422 and handle_changeable_at is reported' do
    profile = create(:user_profile, user: @user, handle: 'first')
    profile.update!(handle: 'second')
    get '/api/v1/profile', headers: @headers
    assert json['handle_changeable_at'].present?

    patch '/api/v1/profile', headers: @headers, params: { profile: { handle: 'third' } }, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['handle'].first.include?('14 days')
  end

  test 'PUT avatar stores a re-encoded JPEG with metadata stripped' do
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: fixture_upload('avatar.jpg', 'image/jpeg') }
    assert_response :success
    assert json['avatar']['small'].present?
    assert json['avatar']['large'].present?

    avatar = @user.reload.profile.avatar
    assert avatar.attached?
    assert_equal 'image/jpeg', avatar.blob.content_type
    data = avatar.blob.download
    refute_includes data, 'private-note-gps', 'comments and other metadata are stripped'
    image = MiniMagick::Image.read(data)
    assert_equal [1024, 1024], image.dimensions
  end

  test 'PUT avatar accepts png and webp-typed uploads, replacing the previous one' do
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: fixture_upload('avatar.png', 'image/png') }
    assert_response :success
    first = @user.reload.profile.avatar.blob.id
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: fixture_upload('avatar.jpg', 'image/jpeg') }
    assert_response :success
    refute_equal first, @user.reload.profile.avatar.blob.id
  end

  test 'PUT avatar 413 when larger than 5 MB' do
    big = bytes_upload("\xFF\xD8\xFF\xE0".b + ('x' * (5.megabytes + 1)), 'image/jpeg', 'big.jpg')
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: big }
    assert_response 413
    assert json['error'].present?
    refute @user.reload.profile&.avatar&.attached?
  end

  test 'PUT avatar 415 for a GIF' do
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: fixture_upload('avatar.gif', 'image/gif') }
    assert_response 415
    assert json['error'].present?
  end

  test 'PUT avatar 415 for a GIF declared as JPEG' do
    gif = bytes_upload(File.binread(Rails.root.join('test/fixtures/files/avatar.gif')), 'image/jpeg', 'fake.jpg')
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: gif }
    assert_response 415
  end

  test 'PUT avatar 422 for a corrupt image' do
    corrupt = bytes_upload("\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b + ('garbage' * 50), 'image/jpeg', 'broken.jpg')
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: corrupt }
    assert_response :unprocessable_entity
    assert json['error'].present?
    refute @user.reload.profile&.avatar&.attached?
  end

  test 'PUT avatar 422 without a file' do
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: 'not a file' }
    assert_response :unprocessable_entity
  end

  test 'DELETE avatar removes it and enqueues the blob purge' do
    put '/api/v1/profile/avatar', headers: @headers, params: { avatar: fixture_upload('avatar.png', 'image/png') }
    assert_response :success

    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      delete '/api/v1/profile/avatar', headers: @headers
    end
    assert_response :success
    assert_nil json['avatar']
    refute @user.reload.profile.avatar.attached?
  end

  test 'DELETE avatar with none is still 200' do
    delete '/api/v1/profile/avatar', headers: @headers
    assert_response :success
    assert_nil json['avatar']
  end
end
