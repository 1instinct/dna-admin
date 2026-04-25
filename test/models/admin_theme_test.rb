require 'test_helper'

class AdminThemeTest < ActiveSupport::TestCase
  setup do
    AdminTheme.delete_all
    Rails.cache.clear
  end

  test "valid with defaults" do
    theme = build(:admin_theme)
    assert theme.valid?
  end

  test "validates hex color format" do
    theme = build(:admin_theme, primary_color: "not-a-color")
    assert_not theme.valid?
    assert theme.errors[:primary_color].any?
  end

  test "validates all color fields are hex" do
    %i[primary_color secondary_color surface_color background_color text_color sidebar_color].each do |field|
      theme = build(:admin_theme, field => "invalid")
      assert_not theme.valid?, "#{field} should require hex format"
    end
  end

  test "validates color_mode inclusion" do
    theme = build(:admin_theme, color_mode: "rainbow")
    assert_not theme.valid?
    assert theme.errors[:color_mode].any?
  end

  test "validates border_radius format" do
    theme = build(:admin_theme, border_radius: "big")
    assert_not theme.valid?
    assert theme.errors[:border_radius].any?

    theme.border_radius = "12px"
    assert theme.valid?
  end

  test "validates font_family characters" do
    theme = build(:admin_theme, font_family: "Inter; } body { display:none")
    assert_not theme.valid?
    assert theme.errors[:font_family].any?
  end

  test "validates brand_name length" do
    theme = build(:admin_theme, brand_name: "a" * 101)
    assert_not theme.valid?
  end

  test "rejects dangerous custom_css" do
    theme = build(:admin_theme, custom_css: "</style><script>alert('xss')</script>")
    assert_not theme.valid?
    assert theme.errors[:custom_css].any?
  end

  test "allows safe custom_css" do
    theme = build(:admin_theme, custom_css: ".my-class { color: red; }")
    assert theme.valid?
  end

  test ".current returns singleton with defaults" do
    theme = AdminTheme.current
    assert_equal '#6366f1', theme.primary_color
    assert_equal 'Admin', theme.brand_name
    assert theme.persisted?
  end

  test ".current caches the result" do
    AdminTheme.current
    assert_equal 1, AdminTheme.count
    AdminTheme.current
    assert_equal 1, AdminTheme.count
  end

  test ".bust_cache! clears the cached theme" do
    AdminTheme.current
    AdminTheme.bust_cache!
    theme = AdminTheme.current
    assert theme.persisted?
  end

  test "singleton_guard prevents duplicate records" do
    create(:admin_theme)
    duplicate = build(:admin_theme)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "logo validation rejects non-image" do
    theme = build(:admin_theme)
    theme.logo.attach(io: StringIO.new("not-an-image"), filename: "file.pdf", content_type: "application/pdf")
    assert_not theme.valid?
    assert theme.errors[:logo].any?
  end

  test "favicon validation rejects oversized file" do
    theme = build(:admin_theme)
    theme.favicon.attach(io: StringIO.new("x" * 600.kilobytes), filename: "big.png", content_type: "image/png")
    assert_not theme.valid?
    assert theme.errors[:favicon].any?
  end
end
