require 'test_helper'

# Public profiles: GET /api/v1/profiles/:handle (auth optional), handle_available (bearer),
# POST/DELETE /api/v1/profiles/:handle/follow (bearer).
class Spree::Api::V1::ProfilesControllerTest < ActionDispatch::IntegrationTest
  PRIVATE_FIELDS = %w[email id user_id first_name last_name firstname lastname address bill_address ship_address].freeze

  setup do
    @owner = create(:user, email: 'owner-secret@example.com')
    @profile = create(:user_profile, user: @owner, handle: 'nova', name: 'Nova', bio: 'beats')
    country = Spree::Country.find_by(iso: 'ZZ') ||
              Spree::Country.create!(name: 'Testland', iso: 'ZZ', iso3: 'ZZZ', iso_name: 'TESTLAND',
                                     states_required: false, zipcode_required: false)
    address = Spree::Address.create!(user: @owner, firstname: 'Realfirst', lastname: 'Reallast', address1: '9 Hidden Rd',
                                     city: 'Town', zipcode: '12345', phone: '555-0100', country: country)
    @owner.update_columns(bill_address_id: address.id, ship_address_id: address.id)
    @viewer = create(:user)
    create(:user_profile, user: @viewer, handle: 'viewer')
  end

  def deep_keys(obj)
    case obj
    when Hash then obj.keys.map(&:to_s) + obj.values.flat_map { |v| deep_keys(v) }
    when Array then obj.flat_map { |v| deep_keys(v) }
    else []
    end
  end

  test 'anonymous GET returns the public profile without private fields' do
    get '/api/v1/profiles/nova'
    assert_response :success
    assert_equal 'nova', json['handle']
    assert_equal 'Nova', json['name']
    assert_equal({ 'is_self' => false, 'following' => false }, json['viewer'])
    assert_empty deep_keys(json) & PRIVATE_FIELDS
    %w[owner-secret@example.com Realfirst Reallast 9\ Hidden\ Rd 555-0100].each do |secret|
      refute_includes response.body, secret
    end
    refute_includes response.body, %("id":#{@owner.id})
  end

  test 'handle lookup is case-insensitive' do
    get '/api/v1/profiles/NoVa'
    assert_response :success
    assert_equal 'nova', json['handle']
  end

  test 'a valid bearer adds viewer state' do
    UserFollow.create!(follower: @viewer, following: @owner)
    get '/api/v1/profiles/nova', headers: auth(@viewer)
    assert_response :success
    assert_equal true, json['viewer']['following']
    assert_equal 1, json['counts']['followers']
  end

  test 'own handle shows is_self' do
    get '/api/v1/profiles/nova', headers: auth(@owner)
    assert_equal true, json['viewer']['is_self']
  end

  test 'an invalid bearer is 401 rather than silently anonymous' do
    get '/api/v1/profiles/nova', headers: bearer('nope')
    assert_response :unauthorized
  end

  test '404 for a missing handle' do
    get '/api/v1/profiles/nobody'
    assert_response :not_found
    assert_equal 'not found', json['error']
  end

  test '404 for a hidden profile' do
    @profile.update_column(:hidden_at, Time.current)
    get '/api/v1/profiles/nova'
    assert_response :not_found
  end

  test '404 for a soft-deleted user' do
    @owner.update_column(:deleted_at, Time.current)
    get '/api/v1/profiles/nova'
    assert_response :not_found
  end

  test '404 for a locked account' do
    @owner.update_column(:locked_at, Time.current)
    get '/api/v1/profiles/nova'
    assert_response :not_found
  end

  test '404 when the owner blocked the viewer' do
    Spree::UserBlock.block!(@owner, @viewer)
    get '/api/v1/profiles/nova', headers: auth(@viewer)
    assert_response :not_found
  end

  test '404 when the viewer blocked the owner' do
    Spree::UserBlock.block!(@viewer, @owner)
    get '/api/v1/profiles/nova', headers: auth(@viewer)
    assert_response :not_found
  end

  test 'private profile returns the reduced payload' do
    @profile.update!(visibility: 'private')
    get '/api/v1/profiles/nova'
    assert_response :success
    assert_equal %w[avatar handle name viewer visibility], json.keys.sort
  end

  test 'handle_available requires a bearer' do
    get '/api/v1/profiles/handle_available', params: { handle: 'free' }
    assert_response :unauthorized
  end

  test 'handle_available reasons' do
    headers = auth(@viewer)
    with_moderation_lists(reserved: %w[admin], blocked: %w[badword]) do
      { 'free_one' => [true, nil], 'NOVA' => [false, 'taken'], 'admin' => [false, 'reserved'],
        'a__b' => [false, 'invalid'], '' => [false, 'invalid'], 'xbadwordx' => [false, 'not_allowed'],
        'viewer' => [true, nil] }.each do |handle, (available, reason)|
        get '/api/v1/profiles/handle_available', params: { handle: handle }, headers: headers
        assert_response :success
        assert_equal({ 'available' => available, 'reason' => reason }, json, handle)
      end
    end
  end

  test 'handle_available ignores the cooldown (the own profile reports handle_changeable_at)' do
    profile = @viewer.profile
    profile.update!(handle: 'viewer2')
    get '/api/v1/profiles/handle_available', params: { handle: 'brand_new' }, headers: auth(@viewer)
    assert_equal({ 'available' => true, 'reason' => nil }, json)
  end

  test 'follow and unfollow by handle, idempotent, with counts' do
    headers = auth(@viewer)
    post '/api/v1/profiles/nova/follow', headers: headers
    assert_response :success
    assert_equal({ 'following' => true, 'followers_count' => 1 }, json)

    post '/api/v1/profiles/NOVA/follow', headers: headers
    assert_response :success
    assert_equal({ 'following' => true, 'followers_count' => 1 }, json)

    delete '/api/v1/profiles/nova/follow', headers: headers
    assert_response :success
    assert_equal({ 'following' => false, 'followers_count' => 0 }, json)

    delete '/api/v1/profiles/nova/follow', headers: headers
    assert_response :success
    assert_equal({ 'following' => false, 'followers_count' => 0 }, json)
  end

  test 'follow requires a bearer' do
    post '/api/v1/profiles/nova/follow'
    assert_response :unauthorized
    delete '/api/v1/profiles/nova/follow'
    assert_response :unauthorized
  end

  test 'follow 403 when a block exists either way' do
    Spree::UserBlock.block!(@owner, @viewer)
    post '/api/v1/profiles/nova/follow', headers: auth(@viewer)
    assert_response :forbidden
    assert json['error'].present?
    delete '/api/v1/profiles/nova/follow', headers: auth(@viewer)
    assert_response :forbidden

    Spree::UserBlock.delete_all
    Spree::UserBlock.block!(@viewer, @owner)
    post '/api/v1/profiles/nova/follow', headers: auth(@viewer)
    assert_response :forbidden
    assert_equal 0, UserFollow.count
  end

  test 'following yourself is 422' do
    post '/api/v1/profiles/nova/follow', headers: auth(@owner)
    assert_response :unprocessable_entity
  end

  test 'follow 404 for missing or hidden profiles' do
    post '/api/v1/profiles/nobody/follow', headers: auth(@viewer)
    assert_response :not_found
    @profile.update_column(:hidden_at, Time.current)
    post '/api/v1/profiles/nova/follow', headers: auth(@viewer)
    assert_response :not_found
  end
end
