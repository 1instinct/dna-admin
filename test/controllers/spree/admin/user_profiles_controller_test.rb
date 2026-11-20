require 'test_helper'

# Profile panel on the admin user page, with hide / unhide and lock / unlock.
class Spree::Admin::UserProfilesControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @user = create(:user)
    @profile = create(:user_profile, user: @user, handle: 'shown', name: 'Shown Name', bio: 'panel bio')
    login_as(@admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'user edit page shows the profile panel' do
    get "/admin/users/#{@user.id}/edit"
    assert_response :success
    assert_includes response.body, 'admin_user_profile_panel'
    assert_includes response.body, '@shown'
    assert_includes response.body, 'panel bio'
  end

  test 'user edit page without a profile says so' do
    other = create(:user)
    get "/admin/users/#{other.id}/edit"
    assert_response :success
    assert_includes response.body, 'admin_user_profile_panel'
    assert_includes response.body, 'No public profile'
  end

  test 'hide and unhide' do
    post "/admin/user_profiles/#{@profile.id}/hide", params: { reason: 'review' }
    assert_response :redirect
    assert @profile.reload.hidden_at.present?
    assert_equal 'review', @profile.hidden_reason

    post "/admin/user_profiles/#{@profile.id}/unhide"
    assert_nil @profile.reload.hidden_at
    assert_nil @profile.hidden_reason
  end

  test 'non-admins cannot hide' do
    login_as(create(:user), scope: :spree_user)
    post "/admin/user_profiles/#{@profile.id}/hide"
    assert_nil @profile.reload.hidden_at
  end
end

class Spree::Admin::AccountLocksControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @user = create(:user)
    login_as(@admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'lock and unlock an account' do
    token = token_for(@user)
    post "/admin/users/#{@user.id}/account_lock"
    assert_response :redirect
    assert @user.reload.locked_at.present?
    assert Doorkeeper.config.access_token_model.by_token(token).revoked?

    delete "/admin/users/#{@user.id}/account_lock"
    assert_nil @user.reload.locked_at
  end

  test 'admins cannot lock themselves' do
    post "/admin/users/#{@admin.id}/account_lock"
    assert_nil @admin.reload.locked_at
  end
end
