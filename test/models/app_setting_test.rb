require 'test_helper'
require 'minitest/mock'

# The mobile app's force-upgrade gate: users below `version` are blocked.
class AppSettingTest < ActiveSupport::TestCase
  NO_LOOKUP = ->(*) { raise 'App Store lookup should not run' }

  # Saves past the App Store guard and pins updated_at so ordering is explicit.
  def gate(version, platform, at)
    setting = AppSetting.create!(version: version, platform: platform, allow_ahead_of_store: true)
    setting.update_columns(updated_at: at)
    setting
  end

  # ── latest / latest_for ──────────────────────────────────────────

  test 'latest_for returns a gate-off default for the asked platform when there are no records' do
    %w[ios android].each do |platform|
      setting = AppSetting.latest_for(platform)
      assert setting.new_record?
      assert_equal '0.0.0', setting.version
      assert_equal platform, setting.platform
      assert_equal 'com.example.app', setting.name
      assert setting.gate_off?
    end
  end

  test 'latest without a platform is unchanged: newest record of any platform' do
    gate('1.0.0', 'ios-android', 3.days.ago)
    android = gate('3.0.0', 'android', 1.day.ago)
    gate('2.0.0', 'ios', 2.days.ago)

    assert_equal android, AppSetting.latest
    assert_equal android, AppSetting.latest_for(nil)
    assert_equal android, AppSetting.latest_for('')
  end

  test 'latest default is unchanged' do
    setting = AppSetting.latest
    assert_equal ['com.example.app', 'ios-android', '0.0.0'], [setting.name, setting.platform, setting.version]
  end

  test 'a newer platform-specific record beats an older ios-android one' do
    gate('1.0.0', 'ios-android', 2.days.ago)
    ios = gate('2.0.0', 'ios', 1.day.ago)

    assert_equal ios, AppSetting.latest_for('ios')
    assert_equal '1.0.0', AppSetting.latest_for('android').version
  end

  test 'a newer ios-android record beats an older platform-specific one' do
    gate('2.0.0', 'ios', 2.days.ago)
    gate('1.5.0', 'android', 2.days.ago)
    both = gate('1.0.0', 'ios-android', 1.day.ago)

    assert_equal both, AppSetting.latest_for('ios')
    assert_equal both, AppSetting.latest_for('android')
  end

  test 'one platform never sees the other platform-only records' do
    gate('9.0.0', 'android', 1.day.ago)

    ios = AppSetting.latest_for('ios')
    assert ios.new_record?
    assert_equal '0.0.0', ios.version
    assert_equal '9.0.0', AppSetting.latest_for('android').version
  end

  test 'unknown platform falls back to latest' do
    gate('1.0.0', 'ios', 2.days.ago)
    android = gate('2.0.0', 'android', 1.day.ago)

    assert_equal android, AppSetting.latest_for('web')
    assert_equal android, AppSetting.latest_for('ios-android')
  end

  test 'platform must be one of the three values' do
    setting = AppSetting.new(version: '0.0.0', platform: 'web')
    refute setting.valid?
    assert setting.errors.include?(:platform)
    assert AppSetting.new(version: '0.0.0', platform: 'android').valid?
  end

  # ── App Store guard ──────────────────────────────────────────────

  test 'refuses an iOS minimum ahead of the live App Store version' do
    asked = nil
    AppStoreLookup.stub(:live_version, ->(id) { asked = id; '1.2.0' }) do
      %w[ios ios-android].each do |platform|
        setting = AppSetting.new(version: '1.3.0', platform: platform)
        refute setting.save
        assert_includes setting.errors.full_messages.join, "Version 1.3.0 isn't live in the App Store yet (live: 1.2.0)"
        assert_includes setting.errors.full_messages.join, "Tick 'Allow ahead of the App Store' to save anyway."
      end
    end
    assert_equal 'com.example.app', asked
    assert_equal 0, AppSetting.count
  end

  test 'allows a minimum at or below the live version' do
    AppStoreLookup.stub(:live_version, '1.2.0') do
      assert AppSetting.create(version: '1.2.0', platform: 'ios').persisted?
      assert AppSetting.create(version: '1.1.9', platform: 'ios-android').persisted?
    end
  end

  test 'compares versions numerically, not as strings' do
    AppStoreLookup.stub(:live_version, '1.10.0') do
      assert AppSetting.create(version: '1.9.0', platform: 'ios').persisted?
    end
  end

  test 'refuses when the app is not on the App Store' do
    AppStoreLookup.stub(:live_version, nil) do
      setting = AppSetting.new(version: '1.0.0', platform: 'ios')
      refute setting.save
      assert_includes setting.errors.full_messages.join, '(live: not found)'
    end
  end

  test 'refuses when the lookup fails' do
    AppStoreLookup.stub(:live_version, ->(*) { raise AppStoreLookup::Error, 'Net::OpenTimeout' }) do
      setting = AppSetting.new(version: '1.0.0', platform: 'ios')
      refute setting.save
      assert_includes setting.errors.full_messages.join, '(live: lookup failed)'
    end
  end

  test 'allow_ahead_of_store saves anyway without a lookup' do
    AppStoreLookup.stub(:live_version, NO_LOOKUP) do
      assert AppSetting.create(version: '5.0.0', platform: 'ios', allow_ahead_of_store: '1').persisted?
    end
  end

  test '0.0.0 (gate off) is always allowed' do
    AppStoreLookup.stub(:live_version, NO_LOOKUP) do
      assert AppSetting.create(version: '0.0.0', platform: 'ios').persisted?
      assert AppSetting.create(version: '0.0.0', platform: 'ios-android').persisted?
    end
  end

  test 'android minimums are not looked up' do
    AppStoreLookup.stub(:live_version, NO_LOOKUP) do
      assert AppSetting.create(version: '5.0.0', platform: 'android').persisted?
    end
  end

  test 'an invalid version is reported without a lookup' do
    AppStoreLookup.stub(:live_version, NO_LOOKUP) do
      setting = AppSetting.new(version: 'banana', platform: 'ios')
      refute setting.save
      assert setting.errors.include?(:version)
    end
  end

  test 'uses the record name as the bundle id' do
    asked = nil
    AppStoreLookup.stub(:live_version, ->(id) { asked = id; '9.0.0' }) do
      AppSetting.create!(version: '1.0.0', platform: 'ios', name: 'com.example.Other')
    end
    assert_equal 'com.example.Other', asked
  end
end
