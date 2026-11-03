require 'test_helper'

class Profiles::PresenterTest < ActiveSupport::TestCase
  PUBLIC_KEYS = %w[handle name bio website avatar links is_creator joined visibility counts viewer sections favorites].freeze
  PRIVATE_KEYS = %w[handle name avatar visibility viewer].freeze
  PRIVATE_FIELDS = %w[email id user_id first_name last_name firstname lastname address addresses bill_address ship_address].freeze

  setup do
    @user = create(:user, email: 'secret-owner@example.com')
    @profile = create(:user_profile, user: @user, handle: 'nova', name: 'Nova', bio: 'beats', website: 'https://nova.example',
                                     links: { 'instagram' => 'nova' })
  end

  def present(profile = @profile, viewer: nil)
    Profiles::Presenter.new(profile, viewer: viewer, base_url: 'https://api.example.com')
  end

  def deep_keys(obj)
    case obj
    when Hash then obj.keys.map(&:to_s) + obj.values.flat_map { |v| deep_keys(v) }
    when Array then obj.flat_map { |v| deep_keys(v) }
    else []
    end
  end

  test 'public json has exactly the spec keys and no private fields' do
    data = present.public_json.as_json
    assert_equal PUBLIC_KEYS.sort, data.keys.sort
    assert_empty deep_keys(data) & PRIVATE_FIELDS
    refute_includes data.to_json, 'secret-owner@example.com'
    refute_includes data.to_json, %("#{@user.id}")
  end

  test 'public json values' do
    @user.update_column(:created_at, Time.utc(2026, 10, 5))
    data = present.public_json.as_json
    assert_equal 'nova', data['handle']
    assert_equal 'Nova', data['name']
    assert_equal 'beats', data['bio']
    assert_equal 'https://nova.example', data['website']
    assert_nil data['avatar']
    assert_equal({ 'instagram' => 'nova' }, data['links'])
    assert_equal false, data['is_creator']
    assert_equal '2026-10', data['joined']
    assert_equal 'public', data['visibility']
    assert_equal({ 'followers' => 0, 'following' => 0 }, data['counts'])
    assert_equal({ 'is_self' => false, 'following' => false }, data['viewer'])
    assert_equal [], data['sections']
    assert_equal [], data['favorites']
  end

  test 'avatar gives small and large variant URLs only' do
    @profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    avatar = present.public_json.as_json['avatar']
    assert_equal %w[large small], avatar.keys.sort
    avatar.each_value do |url|
      assert url.start_with?('https://api.example.com/rails/active_storage/representations/'), url
    end
    refute_equal avatar['small'], avatar['large']
  end

  test 'private visibility returns only handle, name, avatar, visibility and viewer' do
    @profile.update!(visibility: 'private')
    data = present.public_json.as_json
    assert_equal PRIVATE_KEYS.sort, data.keys.sort
    assert_equal 'private', data['visibility']
  end

  test 'private visibility also applies when the owner looks (how others see it)' do
    @profile.update!(visibility: 'private')
    data = present(viewer: @user).public_json.as_json
    assert_equal PRIVATE_KEYS.sort, data.keys.sort
    assert_equal true, data['viewer']['is_self']
  end

  test 'sections contains favorites only when public favorites exist' do
    hidden = create_public_favorite(@user, name: 'Hidden One')
    hidden.update!(is_public: false)
    assert_equal [], present.public_json[:sections]

    fav = create_public_favorite(@user, name: 'Synth Pack', price: 29)
    data = present.public_json.as_json
    assert_equal ['favorites'], data['sections']
    assert_equal 1, data['favorites'].size
    item = data['favorites'].first
    assert_equal %w[image name price product_id slug], item.keys.sort
    assert_equal fav.variant.product.id, item['product_id']
    assert_equal 'Synth Pack', item['name']
    assert_equal '29.00', item['price']
    assert_equal fav.variant.product.slug, item['slug']
  end

  test 'viewer state with a viewer who follows' do
    viewer = create(:user)
    UserFollow.create!(follower: viewer, following: @user)
    UserFollow.create!(follower: @user, following: create(:user))
    data = present(viewer: viewer).public_json.as_json
    assert_equal({ 'is_self' => false, 'following' => true }, data['viewer'])
    assert_equal({ 'followers' => 1, 'following' => 1 }, data['counts'])
  end

  test 'viewer state for the owner' do
    data = present(viewer: @user).public_json.as_json
    assert_equal({ 'is_self' => true, 'following' => false }, data['viewer'])
  end

  test 'own json adds visibility, hidden and handle_changeable_at' do
    data = present(viewer: @user).own_json.as_json
    assert_equal %w[avatar bio counts handle handle_changeable_at hidden is_creator joined links name visibility website].sort,
                 data.keys.sort
    assert_equal false, data['hidden']
    assert_nil data['handle_changeable_at']
    assert_empty deep_keys(data) & PRIVATE_FIELDS

    @profile.update!(handle: 'nova2')
    @profile.update_column(:hidden_at, Time.current)
    data = present(viewer: @user).own_json.as_json
    assert_equal true, data['hidden']
    assert_equal (@profile.handle_changed_at + 14.days).iso8601, Time.iso8601(data['handle_changeable_at']).iso8601
  end

  test 'own json for a user with no profile row' do
    user = create(:user)
    data = Profiles::Presenter.new(user.profile || user.build_profile, viewer: user, base_url: 'https://x.test').own_json.as_json
    assert_nil data['handle']
    assert_equal 'public', data['visibility']
    assert_equal({}, data['links'])
    refute Spree::UserProfile.exists?(user_id: user.id), 'presenting does not save'
  end

  test 'identity json for block lists' do
    data = present.identity_json.as_json
    assert_equal %w[avatar handle name], data.keys.sort
  end
end
