require 'test_helper'

# Visitors::Tracker: visit pings become sessions (30-minute window) and page views.
class Visitors::TrackerTest < ActiveSupport::TestCase
  include ChatTestHelper

  IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148'.freeze
  IPAD = 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148'.freeze
  ANDROID_PHONE = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36'.freeze
  ANDROID_TABLET = 'Mozilla/5.0 (Linux; Android 13; SM-X700) AppleWebKit/537.36 Chrome/120.0 Safari/537.36'.freeze
  MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15'.freeze

  setup do
    @contact = chat_contact
    @info = { user_agent: IPHONE, ip: '203.0.113.77', country: 'DE' }
    @tracker = Visitors::Tracker.new(@contact, @info)
  end

  teardown { Visitors.reset_config! }

  test 'the first ping starts a session with the request details' do
    session = @tracker.ping(url: 'https://shop.example.com/', title: 'Home', referrer: 'https://search.example.org/',
                            utm: { 'source' => 'news', 'medium' => 'email', 'campaign' => 'launch' })

    assert_equal ['https://shop.example.com/', 'Home', 'https://search.example.org/'],
                 [session.current_url, session.current_title, session.referrer]
    assert_equal %w[news email launch], [session.utm_source, session.utm_medium, session.utm_campaign]
    assert_equal ['mobile', '203.0.113.0', 'DE'], [session.device, session.ip, session.country]
    assert_equal 1, session.page_views
    assert session.token.present?
    assert_equal [['https://shop.example.com/', 'Home']], session.pages.map { |p| [p.url, p.title] }
    assert @contact.reload.last_seen_at.present?
  end

  test 'pings within 30 minutes extend the session; heartbeats on the same page are not page views' do
    first = @tracker.ping(url: '/a', title: 'A')
    travel 1.minute do
      assert_equal first, @tracker.ping(url: '/a', title: 'A')
    end
    travel 29.minutes do
      @tracker.ping(url: '/b', title: 'B')
    end
    travel 58.minutes do
      session = @tracker.ping(url: '/a', title: 'A again')
      assert_equal first, session
      assert_equal 3, session.page_views
      assert_equal %w[/a /b /a], session.pages.reverse.map(&:url)
      assert_equal 'A again', session.current_title
    end
  end

  test 'thirty minutes without a ping ends the session, and the next ping starts another' do
    first = @tracker.ping(url: '/a')

    travel 31.minutes do
      second = @tracker.ping(url: '/a')
      refute_equal first, second
      assert_equal 1, second.page_views
      assert_equal 2, @contact.visitor_sessions.count
    end
  end

  test 'utm fills a session that had none, and never replaces one' do
    session = @tracker.ping(url: '/a')
    @tracker.ping(url: '/b', utm: { source: 'ad' })
    @tracker.ping(url: '/c', utm: { source: 'other' })

    assert_equal 'ad', session.reload.utm_source
  end

  test 'the cart is linked from the order token, never a completed order or a stranger token' do
    cart = chat_cart
    session = @tracker.ping(url: '/cart', order_token: cart.token)
    assert_equal cart, session.order

    done = completed_order
    @tracker.ping(url: '/done', order_token: done.token)
    @tracker.ping(url: '/x', order_token: 'not-a-token')
    assert_equal cart, session.reload.order
  end

  test 'a signed-in customer’s current cart is used when there is no order token' do
    user = create(:user)
    older = chat_cart(user: user)
    older.update_columns(updated_at: 1.day.ago)
    current = chat_cart(user: user)
    guest = chat_cart

    assert_equal current, @tracker.ping(url: '/a', user: user).order
    assert_equal guest, @tracker.ping(url: '/b', user: user, order_token: guest.token).order
  end

  test 'devices from the user agent' do
    assert_equal 'mobile', Visitors::Tracker.device_for(IPHONE)
    assert_equal 'mobile', Visitors::Tracker.device_for(ANDROID_PHONE)
    assert_equal 'tablet', Visitors::Tracker.device_for(IPAD)
    assert_equal 'tablet', Visitors::Tracker.device_for(ANDROID_TABLET)
    assert_equal 'desktop', Visitors::Tracker.device_for(MAC)
    assert_equal 'desktop', Visitors::Tracker.device_for(nil)
  end

  test 'IPs are kept to their /24 or /48' do
    assert_equal '198.51.100.0', Visitors::Tracker.truncate_ip('198.51.100.200')
    assert_equal '2001:db8:abcd::', Visitors::Tracker.truncate_ip('2001:db8:abcd:12:3456:789a:bcde:f012')
    assert_equal '192.0.2.0', Visitors::Tracker.truncate_ip('::ffff:192.0.2.9')
    assert_nil Visitors::Tracker.truncate_ip('not an ip')
    assert_nil Visitors::Tracker.truncate_ip(nil)
  end

  test 'country from CF-IPCountry or X-Country, two letters only' do
    request = ActionDispatch::TestRequest.create('HTTP_CF_IPCOUNTRY' => 'fr', 'HTTP_USER_AGENT' => MAC,
                                                 'REMOTE_ADDR' => '203.0.113.5')
    assert_equal({ user_agent: MAC, ip: '203.0.113.5', country: 'FR' }, Visitors::Tracker.request_info(request))
    assert_equal 'NL', Visitors::Tracker.request_info(ActionDispatch::TestRequest.create('HTTP_X_COUNTRY' => 'NL'))[:country]
    assert_nil Visitors::Tracker.country_from('XX')
    assert_nil Visitors::Tracker.country_from('T1')
    assert_nil Visitors::Tracker.country_from('Germany')
  end

  test 'long or odd values are clipped, and nested ones ignored' do
    session = @tracker.ping(url: "/#{'a' * 3000}", title: 'T' * 400, referrer: { 'x' => 1 }, utm: 'nope')

    assert_equal 2048, session.current_url.length
    assert_equal 255, session.current_title.length
    assert_nil session.referrer
    assert_nil session.utm_source
  end

  test 'rake visitors:prune drops page views older than 30 days' do
    session = @tracker.ping(url: '/new')
    old = VisitorPageView.create!(visitor_session: session, url: '/old', created_at: 31.days.ago)

    assert_equal 1, Visitors.prune!
    refute VisitorPageView.exists?(old.id)
    assert_equal ['/new'], session.pages.map(&:url)

    VisitorPageView.create!(visitor_session: session, url: '/older', created_at: 40.days.ago)
    Rails.application.load_tasks unless Rake::Task.task_defined?('visitors:prune')
    assert_output(/visitors:prune deleted 1 page view/) { Rake::Task['visitors:prune'].execute }
  end
end
