require 'test_helper'

# The older id-based GET users/:id/profile follows the same visibility rules as
# GET profiles/:handle: 404 for hidden and locked, no favorites or counts when private.
class Spree::Api::V1::LegacyUserProfileTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create(:user)
    @viewer = create(:user)
    @product = media_product
    Favorite.create!(user: @owner, variant: @product.master, is_public: true)
    UserFollow.create!(follower: @viewer, following: @owner)
  end

  def get_profile(headers: {})
    get "/api/v1/users/#{@owner.id}/profile.json", headers: headers
    json['response_data']
  end

  test '404 for a hidden profile, anonymous or signed in' do
    profile = create(:user_profile, user: @owner, handle: 'hidden_one')
    Profiles::Moderation.hide(profile)

    get_profile
    assert_equal 404, json['response_code']
    get_profile(headers: auth(@viewer))
    assert_equal 404, json['response_code']
  end

  test '404 for a locked account' do
    Profiles::Moderation.lock(@owner)

    get_profile
    assert_equal 404, json['response_code']
    refute_includes response.body, @product.slug
  end

  test 'a private profile shows others no favorites or counts' do
    create(:user_profile, user: @owner, handle: 'private_one', visibility: 'private')

    [{}, auth(@viewer)].each do |headers|
      data = get_profile(headers: headers)
      assert_equal 200, json['response_code']
      assert_equal @owner.id, data['id']
      assert_equal '', data['email']
      %w[public_favorites followers_count following_count].each { |key| refute data.key?(key), key }
      refute_includes response.body, @product.slug
    end
    assert_equal true, get_profile(headers: auth(@viewer))['is_following']
  end

  test 'the owner still sees their own private profile in full' do
    create(:user_profile, user: @owner, handle: 'private_one', visibility: 'private')

    data = get_profile(headers: auth(@owner))
    assert_equal 200, json['response_code']
    assert_equal 1, data['followers_count']
    assert_equal [@product.slug], data['public_favorites'].map { |f| f['slug'] }
    assert_equal '', data['email']
  end

  test 'a public profile, or a user with no profile, is unchanged' do
    data = get_profile
    assert_equal 1, data['followers_count']
    assert_equal [@product.slug], data['public_favorites'].map { |f| f['slug'] }

    create(:user_profile, user: @owner, handle: 'public_one')
    data = get_profile
    assert_equal 1, data['followers_count']
    assert_equal [@product.slug], data['public_favorites'].map { |f| f['slug'] }
  end
end
