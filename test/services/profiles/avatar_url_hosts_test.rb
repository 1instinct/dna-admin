require 'test_helper'

# An external avatar URL reaches viewers' devices, so its host sees their IP. Only hosts named in
# PROFILE_AVATAR_URL_HOSTS are ever served; the default is none.
class Profiles::AvatarUrlHostsTest < ActiveSupport::TestCase
  setup do
    @old_hosts = ENV['PROFILE_AVATAR_URL_HOSTS']
    ENV.delete('PROFILE_AVATAR_URL_HOSTS')
    Profiles.reset_config!
    @profile = create(:user_profile, handle: 'hosted')
  end

  teardown do
    ENV['PROFILE_AVATAR_URL_HOSTS'] = @old_hosts
    Profiles.reset_config!
  end

  def allow_hosts(value)
    ENV['PROFILE_AVATAR_URL_HOSTS'] = value
    Profiles.reset_config!
  end

  test 'nothing is allowed by default' do
    assert_empty Profiles.config.avatar_url_hosts
    refute Profiles.config.avatar_url_allowed?('https://cdn.example/a.png')
  end

  test 'parses a comma-separated list, ignoring case and spaces' do
    allow_hosts(' CDN.example , img.example,')
    assert_equal %w[cdn.example img.example], Profiles.config.avatar_url_hosts
  end

  test 'matches the exact host over https only' do
    allow_hosts('cdn.example')
    assert Profiles.config.avatar_url_allowed?('https://CDN.example/a.png')
    refute Profiles.config.avatar_url_allowed?('http://cdn.example/a.png')
    refute Profiles.config.avatar_url_allowed?('https://evil.cdn.example/a.png')
    refute Profiles.config.avatar_url_allowed?('https://cdn.example.evil.example/a.png')
    refute Profiles.config.avatar_url_allowed?('https://cdn.example@evil.example/a.png')
    refute Profiles.config.avatar_url_allowed?('https://cdn.example:not a port/a.png')
    refute Profiles.config.avatar_url_allowed?(nil)
    refute Profiles.config.avatar_url_allowed?('')
  end

  test 'the presenter drops a fallback whose host is not allowed' do
    Profiles.config.avatar_fallback = ->(_user) { 'https://elsewhere.example/a.png' }
    assert_nil Profiles::Presenter.new(@profile).avatar
  end

  test 'the presenter serves a fallback on an allowed host for every size' do
    allow_hosts('cdn.example')
    Profiles.config.avatar_fallback = ->(_user) { 'https://cdn.example/a.png' }
    assert_equal({ small: 'https://cdn.example/a.png', large: 'https://cdn.example/a.png' },
                 Profiles::Presenter.new(@profile).avatar)
  end
end
