require 'test_helper'

class Spree::Admin::HomepageSectionsControllerTest < ActionDispatch::IntegrationTest
  include Spree::Core::Engine.routes.url_helpers
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = Spree::User.create!(email: "homepage-sections-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @admin.generate_spree_api_key!
    sign_in @admin, scope: :spree_user
  end

  test 'composes announcement_bar settings from discrete fields' do
    post admin_homepage_sections_path, params: { homepage_section: {
      title: 'Bar', section_type: 'announcement_bar', position: 0, is_visible: '1',
      settings_fields: { message: 'Beta is open', cta_label: 'Join', dismissible: '1',
                         starts_at: '', ends_at: '2026-12-01T00:00:00Z' }
    } }
    settings = HomepageSection.last.settings
    assert_kind_of Hash, settings
    assert_equal 'Beta is open', settings['message']
    assert_equal 'Join', settings['cta_label']
    assert_equal true, settings['dismissible']
    assert_nil settings['starts_at']
    assert_equal '2026-12-01T00:00:00Z', settings['ends_at']
  end

  test 'casts an unchecked dismissible box to false' do
    post admin_homepage_sections_path, params: { homepage_section: {
      title: 'Bar', section_type: 'announcement_bar', position: 0,
      settings_fields: { message: 'Hi', dismissible: '0' }
    } }
    assert_equal false, HomepageSection.last.settings['dismissible']
  end

  test 'ignores fields from the other fieldset and the raw textarea' do
    post admin_homepage_sections_path, params: { homepage_section: {
      title: 'Links', section_type: 'app_links', position: 0, settings: 'garbage',
      settings_fields: { ios_url: 'https://apps.apple.com/app/id1', message: 'stray' }
    } }
    assert_equal({ 'ios_url' => 'https://apps.apple.com/app/id1' }, HomepageSection.last.settings)
  end

  test 'composes app_links settings and round-trips on update' do
    section = HomepageSection.create!(title: 'Links', section_type: 'app_links', position: 0,
                                      settings: { 'ios_url' => '', 'android_url' => '' })
    patch admin_homepage_section_path(section), params: { homepage_section: {
      settings_fields: { ios_url: 'https://apps.apple.com/app/id1234567890' }
    } }
    section.reload
    assert_equal 'https://apps.apple.com/app/id1234567890', section.settings['ios_url']
    assert_equal '', section.settings['android_url']
    assert_kind_of Hash, section.settings
  end

  test 'edit form renders discrete fields prefilled from the stored hash' do
    section = HomepageSection.create!(title: 'Bar', section_type: 'announcement_bar', position: 0,
                                      settings: { 'message' => 'Beta is open', 'dismissible' => true })
    get edit_admin_homepage_section_path(section)
    assert_response :ok
    assert_select 'input[name="homepage_section[settings_fields][message]"][value=?]', 'Beta is open'
    assert_select 'input[type=checkbox][name="homepage_section[settings_fields][dismissible]"][checked]'
    assert_select 'input[name="homepage_section[settings_fields][ios_url]"]'
  end

  test 'new form renders both fieldsets' do
    get new_admin_homepage_section_path
    assert_response :ok
    assert_select 'input[name="homepage_section[settings_fields][message]"]'
    assert_select 'input[name="homepage_section[settings_fields][android_url]"]'
  end

  test 'leaves the raw settings textarea behaviour intact for other types' do
    post admin_homepage_sections_path, params: { homepage_section: {
      title: 'Hero', section_type: 'hero', position: 0, settings: '{"a":1}',
      settings_fields: { message: 'ignored' }
    } }
    section = HomepageSection.last
    assert_equal 'hero', section.section_type
    # Pre-existing behaviour, deliberately unchanged: the textarea value is stored as a JSON string.
    assert_equal '{"a":1}', section.settings
  end

  test 'rejects a scheme-less store url instead of flashing success' do
    assert_no_difference 'HomepageSection.count' do
      post admin_homepage_sections_path, params: { homepage_section: {
        title: 'Links', section_type: 'app_links', position: 0,
        settings_fields: { ios_url: 'apps.apple.com/app/id1234567890' }
      } }
    end
    assert_response :ok # re-rendered :new, not a redirect
    assert_match(/iOS App Store URL/, flash[:error].to_s)
    assert_nil flash[:success]
  end

  test 'rejects a scheme-less announcement cta_href' do
    assert_no_difference 'HomepageSection.count' do
      post admin_homepage_sections_path, params: { homepage_section: {
        title: 'Bar', section_type: 'announcement_bar', position: 0,
        settings_fields: { message: 'Hi', cta_href: 'example.com/app' }
      } }
    end
    assert_match(/Button link/, flash[:error].to_s)
  end

  test 'hides the raw settings textarea for the composed section types' do
    %w[app_links announcement_bar].each do |type|
      section = HomepageSection.create!(title: type, section_type: type, position: 0, settings: {})
      get edit_admin_homepage_section_path(section)
      assert_response :ok
      assert_select 'textarea[name="homepage_section[settings]"]', false,
                    "#{type} should not offer the raw settings textarea"
      assert_select 'input[name="homepage_section[settings_fields][ios_url]"]'
    end
  end

  test 'keeps the raw settings textarea for every other section type' do
    section = HomepageSection.create!(title: 'Hero', section_type: 'hero', position: 0, settings: '{"a":1}')
    get edit_admin_homepage_section_path(section)
    assert_select 'textarea[name="homepage_section[settings]"]'
  end

  test 'sets flash from locale keys, not translation-missing strings' do
    post admin_homepage_sections_path, params: { homepage_section: {
      title: 'Hero', section_type: 'hero', position: 0
    } }
    assert_no_match(/translation missing/i, flash[:success].to_s)
    assert_equal 'Homepage section was successfully created.', flash[:success]
  end
end
