require 'test_helper'

class AffiliateClickTest < ActiveSupport::TestCase
  teardown { Affiliates.reset_config! }

  test 'visitor_hash never equals the raw ip and changes daily' do
    ip = '203.0.113.7'
    ua = 'Mozilla/5.0'
    today = AffiliateClick.visitor_hash(ip: ip, user_agent: ua, date: Date.new(2026, 11, 14))
    again = AffiliateClick.visitor_hash(ip: ip, user_agent: ua, date: Date.new(2026, 11, 14))
    tomorrow = AffiliateClick.visitor_hash(ip: ip, user_agent: ua, date: Date.new(2026, 11, 15))

    refute_equal ip, today
    refute_includes today, ip
    assert_match(/\A[0-9a-f]{64}\z/, today)
    assert_equal today, again
    refute_equal today, tomorrow
  end

  test 'visitor_hash depends on the salt and the user agent' do
    date = Date.new(2026, 11, 14)
    a = AffiliateClick.visitor_hash(ip: '203.0.113.7', user_agent: 'A', date: date)
    b = AffiliateClick.visitor_hash(ip: '203.0.113.7', user_agent: 'B', date: date)
    refute_equal a, b

    Affiliates.config.visitor_salt = 'another-salt'
    refute_equal a, AffiliateClick.visitor_hash(ip: '203.0.113.7', user_agent: 'A', date: date)
  end

  test 'referrer_host_for keeps only the host' do
    assert_equal 'www.youtube.com', AffiliateClick.referrer_host_for('https://www.youtube.com/watch?v=abc&email=x@y.z')
    assert_nil AffiliateClick.referrer_host_for('not a url')
    assert_nil AffiliateClick.referrer_host_for(nil)
  end

  test 'landing_path_for keeps only the path' do
    assert_equal '/products/x', AffiliateClick.landing_path_for('/products/x?ref=abc&email=a@b.c')
    assert_equal '/products/x', AffiliateClick.landing_path_for('https://shop.example.com/products/x?ref=abc')
    assert_equal '/', AffiliateClick.landing_path_for(nil)
    assert_equal 255, AffiliateClick.landing_path_for("/#{'a' * 400}").length
  end
end
