require 'test_helper'

# Blocks also apply to the older id-based user endpoints (users/:id/profile, follow).
class Spree::Api::V1::LegacyUserBlocksTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create(:user)
    @viewer = create(:user)
    @viewer.generate_spree_api_key!
  end

  test 'a follow cannot be created while a block exists' do
    Spree::UserBlock.block!(@owner, @viewer)
    follow = UserFollow.new(follower: @viewer, following: @owner)
    refute follow.valid?
  end

  test 'POST users/:id/follow is refused when blocked either way' do
    Spree::UserBlock.block!(@owner, @viewer)
    post "/api/v1/users/#{@owner.id}/follow.json", headers: auth(@viewer)
    assert_equal 403, json["response_code"], "legacy envelope: the code is in the body"
    assert_equal 0, UserFollow.count
  end

  test 'GET users/:id/profile is 404 for a viewer in a block' do
    Spree::UserBlock.block!(@viewer, @owner)
    get "/api/v1/users/#{@owner.id}/profile.json", headers: auth(@viewer)
    assert_equal 404, json["response_code"]

    get "/api/v1/users/#{@owner.id}/profile.json"
    assert_equal 200, json["response_code"], "anonymous still works for the web"
  end
end
