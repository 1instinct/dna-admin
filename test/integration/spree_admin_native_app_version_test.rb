require 'test_helper'

# The companion gem's admin app version gate is installed: its table migrates, the endpoint
# answers and the capability is announced.
class SpreeAdminNativeAppVersionTest < ActionDispatch::IntegrationTest
  teardown { SpreeAdminNative::AppVersion.delete_all }

  test 'no gate until one is set' do
    get '/api/admin_native/v1/app_version', params: { platform: 'ios', version: '1.0.0' }
    assert_response :success
    data = JSON.parse(response.body)['data']
    assert_nil data['minimum_version']
    assert_equal false, data['update_required']
  end

  test 'a minimum and a recommended version reach the app' do
    SpreeAdminNative::AppVersion.create!(platform: 'all', minimum_version: '1.0.0', recommended_version: '1.2.0',
                                         update_url: 'https://apps.apple.com/app/id1', allow_ahead_of_store: true)
    get '/api/admin_native/v1/app_version', params: { platform: 'ios', version: '1.1.0' }
    data = JSON.parse(response.body)['data']
    assert_equal [false, true], [data['update_required'], data['update_recommended']]
    assert_equal 'https://apps.apple.com/app/id1', data['update_url']

    get '/api/admin_native/v1/capabilities'
    assert_includes JSON.parse(response.body)['capabilities'], 'app.versionGate'
  end
end
