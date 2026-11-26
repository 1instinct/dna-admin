require 'test_helper'

# GET /api/v1/app_settings/latest: the app's force-upgrade gate. Newer builds send ?platform=;
# older builds don't and must keep getting the platform-blind answer.
class Spree::Api::V1::AppSettingsControllerTest < ActionDispatch::IntegrationTest
  def gate(version, platform, at)
    setting = AppSetting.create!(version: version, platform: platform, allow_ahead_of_store: true, build: "b#{version}")
    setting.update_columns(updated_at: at)
    setting
  end

  def latest(params = {})
    get '/api/v1/app_settings/latest', params: params
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 200, body['response_code']
    body['response_data']
  end

  test 'no records: gate-off default, with the asked platform' do
    assert_equal({ 'name' => 'com.example.app', 'platform' => 'ios-android', 'version' => '0.0.0', 'build' => nil }, latest)
    assert_equal({ 'name' => 'com.example.app', 'platform' => 'ios', 'version' => '0.0.0', 'build' => nil }, latest(platform: 'ios'))
    assert_equal 'android', latest(platform: 'android')['platform']
  end

  test 'without a platform, the newest record of any platform (older apps)' do
    gate('1.0.0', 'ios-android', 2.days.ago)
    gate('3.0.0', 'android', 1.day.ago)

    data = latest
    assert_equal '3.0.0', data['version']
    assert_equal 'android', data['platform']
    assert_equal 'b3.0.0', data['build']
  end

  test 'with a platform, the newest record for it or for both' do
    gate('1.0.0', 'ios-android', 3.days.ago)
    gate('2.0.0', 'ios', 2.days.ago)
    gate('3.0.0', 'android', 1.day.ago)

    assert_equal %w[2.0.0 ios], latest(platform: 'ios').values_at('version', 'platform')
    assert_equal %w[3.0.0 android], latest(platform: 'android').values_at('version', 'platform')
  end

  test 'a newer ios-android record beats an older platform-specific one' do
    gate('2.0.0', 'ios', 2.days.ago)
    gate('1.0.0', 'ios-android', 1.day.ago)

    assert_equal %w[1.0.0 ios-android], latest(platform: 'ios').values_at('version', 'platform')
  end

  test 'unknown platform is treated as absent' do
    gate('1.0.0', 'ios', 2.days.ago)
    gate('2.0.0', 'android', 1.day.ago)

    assert_equal '2.0.0', latest(platform: 'web')['version']
    assert_equal '2.0.0', latest(platform: '')['version']
  end
end
