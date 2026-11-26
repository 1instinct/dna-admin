require 'test_helper'

class HomepageSectionTest < ActiveSupport::TestCase
  test 'accepts the announcement_bar section type' do
    section = HomepageSection.new(title: 'Bar', section_type: 'announcement_bar', position: 0)
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'accepts the app_links section type' do
    section = HomepageSection.new(title: 'App links', section_type: 'app_links', position: 0)
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'still rejects an unknown section type' do
    assert_not HomepageSection.new(title: 'X', section_type: 'nope', position: 0).valid?
  end

  # The storefront only follows an absolute http(s) URL (lib/appLinks.ts), so a
  # scheme-less paste is silently discarded there and the site keeps showing the
  # old link. Fail loudly here instead.
  def app_links(settings)
    HomepageSection.new(title: 'App links', section_type: 'app_links', position: 0, settings: settings)
  end

  def announcement_bar(settings)
    HomepageSection.new(title: 'Bar', section_type: 'announcement_bar', position: 0, settings: settings)
  end

  test 'app_links accepts blank urls' do
    section = app_links('ios_url' => '', 'android_url' => nil)
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'app_links accepts absolute https urls' do
    section = app_links('ios_url' => 'https://apps.apple.com/app/id1234567890',
                        'android_url' => 'http://play.google.com/store/apps/details?id=com.example.app')
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'app_links rejects a scheme-less ios url and names the field' do
    section = app_links('ios_url' => 'apps.apple.com/app/id1234567890')
    assert_not section.valid?
    assert_match(/iOS App Store URL/, section.errors.full_messages.join(', '))
    assert_match(%r{https://}, section.errors.full_messages.join(', '))
  end

  test 'app_links rejects a scheme-less android url and names the field' do
    section = app_links('android_url' => 'play.google.com/store/apps/details?id=com.example.app')
    assert_not section.valid?
    assert_match(/Google Play URL/, section.errors.full_messages.join(', '))
  end

  test 'app_links rejects a javascript: url' do
    assert_not app_links('ios_url' => 'javascript:alert(1)').valid?
    assert_not app_links('android_url' => 'javascript:alert(1)').valid?
  end

  test 'announcement_bar accepts a blank cta_href' do
    section = announcement_bar('message' => 'Hi', 'cta_href' => '')
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'announcement_bar accepts an absolute https cta_href' do
    section = announcement_bar('message' => 'Hi', 'cta_href' => 'https://example.com/app')
    assert section.valid?, section.errors.full_messages.join(', ')
  end

  test 'announcement_bar rejects a scheme-less cta_href and names the field' do
    section = announcement_bar('message' => 'Hi', 'cta_href' => 'example.com/app')
    assert_not section.valid?
    assert_match(/Button link/, section.errors.full_messages.join(', '))
  end

  test 'announcement_bar rejects a javascript: cta_href' do
    assert_not announcement_bar('message' => 'Hi', 'cta_href' => 'javascript:alert(1)').valid?
  end

  test 'other section types are not url-validated' do
    section = HomepageSection.new(title: 'Hero', section_type: 'hero', position: 0, settings: '{"cta_href":"nope"}')
    assert section.valid?, section.errors.full_messages.join(', ')
  end
end
