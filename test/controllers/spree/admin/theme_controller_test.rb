require 'test_helper'
require 'minitest/mock'

class Spree::Admin::ThemeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Spree::Core::Engine.routes.url_helpers

  setup do
    AdminTheme.delete_all
    Rails.cache.clear
    @admin = Spree.user_class.create!(email: "theme-admin-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    sign_in @admin, scope: :spree_user
  end

  test "GET show renders theme editor" do
    get admin_theme_path
    assert_response :ok
  end

  test "GET show creates default theme if none exists" do
    assert_equal 0, AdminTheme.count
    get admin_theme_path
    assert_equal 1, AdminTheme.count
  end

  test "PUT update saves theme and busts cache" do
    AdminTheme.current
    put admin_theme_path, params: {
      admin_theme: { primary_color: '#ff0000', brand_name: 'My Brand' }
    }
    assert_redirected_to admin_theme_path
    theme = AdminTheme.first
    assert_equal '#ff0000', theme.primary_color
    assert_equal 'My Brand', theme.brand_name
  end

  test "PUT update with invalid data re-renders form" do
    AdminTheme.current
    put admin_theme_path, params: {
      admin_theme: { primary_color: 'not-hex' }
    }
    assert_response :ok
  end

  test "PUT update with logo upload" do
    AdminTheme.current
    file = fixture_file_upload("test/fixtures/files/test-image.png", "image/png")
    put admin_theme_path, params: { admin_theme: { logo: file } }
    assert_redirected_to admin_theme_path
    assert AdminTheme.first.logo.attached?
  end

  test "GET show renders with logo and favicon attached" do
    theme = AdminTheme.current
    theme.logo.attach(fixture_file_upload("test/fixtures/files/test-image.png", "image/png"))
    theme.favicon.attach(fixture_file_upload("test/fixtures/files/test-image.png", "image/png"))
    theme.save!
    AdminTheme.bust_cache!

    get admin_theme_path
    assert_response :ok
    assert_select "input[type=checkbox][name='admin_theme[remove_logo]']"
    assert_select "input[type=checkbox][name='admin_theme[remove_favicon]']"
    assert_select "img.admin-logo"
  end

  test "PUT update with remove_logo purges the logo" do
    theme = AdminTheme.current
    theme.logo.attach(fixture_file_upload("test/fixtures/files/test-image.png", "image/png"))
    theme.save!

    put admin_theme_path, params: { admin_theme: { brand_name: 'Kept', remove_logo: '1' } }
    assert_redirected_to admin_theme_path
    assert_not AdminTheme.first.logo.attached?
  end

  test "admin pages render with default theme when admin_themes table is missing" do
    AdminTheme.stub(:table_exists?, false) do
      get admin_homepage_sections_path
    end
    assert_response :ok
    assert_includes response.body, "--admin-primary: #6366f1"
  end
end
