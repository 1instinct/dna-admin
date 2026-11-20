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
end
