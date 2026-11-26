require 'test_helper'
require 'minitest/mock'

# Admin "App Settings": the version gate form, with the App Store lock-out guard.
class Spree::Admin::AppSettingsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    login_as(@admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  def submit(attrs)
    post '/admin/app_settings', params: { app_setting: { name: 'com.example.app', build: '' }.merge(attrs) }
    assert_redirected_to '/admin/app_settings'
  end

  test 'refuses an iOS minimum ahead of the App Store with the reason' do
    AppStoreLookup.stub(:live_version, nil) do
      submit(version: '2.6.0', platform: 'ios', allow_ahead_of_store: '0')
    end
    assert_equal 0, AppSetting.count
    assert_includes flash[:error], "Version 2.6.0 isn't live in the App Store yet (live: not found)"
  end

  test 'the override checkbox reaches the model' do
    AppStoreLookup.stub(:live_version, ->(*) { flunk 'no lookup with the override' }) do
      submit(version: '2.6.0', platform: 'ios-android', allow_ahead_of_store: '1')
    end
    assert_equal '2.6.0', AppSetting.last.version
    assert_equal 'App setting v2.6.0 created.', flash[:success]
  end

  test 'refuses an unknown platform' do
    submit(version: '0.0.0', platform: 'web')
    assert_equal 0, AppSetting.count
    assert_match(/Platform/, flash[:error])
  end

  test 'index shows the gate per platform, the override and the Android note' do
    AppSetting.create!(version: '1.0.0', platform: 'ios-android', allow_ahead_of_store: true).update_columns(updated_at: 2.days.ago)
    AppSetting.create!(version: '2.0.0', platform: 'android').update_columns(updated_at: 1.day.ago)

    get '/admin/app_settings'
    assert_response :success
    html = Nokogiri::HTML(response.body)
    assert_includes html.at_css('#gate_ios').text, '1.0.0'
    assert_includes html.at_css('#gate_android').text, '2.0.0'
    assert html.at_css('input[type=checkbox][name="app_setting[allow_ahead_of_store]"]')
    assert_includes response.body, 'Allow ahead of the App Store'
    assert_includes response.body, "Android minimums aren't checked against Google Play"
  end
end
