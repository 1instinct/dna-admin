require 'test_helper'

# The Rails admin's Visitors pages (/admin/visitors, Spree::Admin::VisitorsController): online
# sessions over Visitors::Adapter, active and abandoned carts over SpreeAdminNative::Carts, a
# visit's timeline, starting a conversation from a visit, and admin-only access.
class Spree::Admin::VisitorsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ChatTestHelper

  setup do
    @admin = chat_admin(email: 'visitors-admin@example.com')
    login_as(@admin, scope: :spree_user)
    @contact = chat_contact(name: 'Ada Example', email: 'ada@example.com')
    @cart = chat_cart(email: 'ada@example.com')
    tracker = Visitors::Tracker.new(@contact, user_agent: 'iPhone Mobile', ip: '203.0.113.7', country: 'DE')
    tracker.ping(url: 'https://shop.example.com/', title: 'Home', now: 3.minutes.ago)
    @session = tracker.ping(url: 'https://shop.example.com/mug', title: 'Blue mug', utm: { source: 'news', medium: 'email' },
                            order_token: @cart.token)
    other = chat_contact(visitor_token: Contact.generate_visitor_token, name: 'Ben Gone', email: 'ben@example.com')
    @offline = Visitors::Tracker.new(other).ping(url: 'https://shop.example.com/old', now: 20.minutes.ago)
  end

  teardown { Warden.test_reset! }

  def json(method, path)
    send(method, path, headers: { 'ACCEPT' => 'application/json' })
    JSON.parse(response.body)
  end

  test 'Live lists online sessions with page, device, country, campaign, cart and a Message button' do
    get '/admin/visitors'
    assert_response :success
    assert_select '.nav-tabs a.nav-link.active', text: 'Live'
    assert_select '[data-role=count]', text: '1'
    assert_select "tr[data-session='#{@session.id}']" do
      assert_select 'a', text: 'Ada Example'
      assert_select 'td', text: /Blue mug/
      assert_select 'td', text: 'mobile'
      assert_select 'td', text: 'DE'
      assert_select 'td', text: 'news / email'
      assert_select "a[href='/admin/orders/#{@cart.number}/cart']", text: /2 items · 25.00 USD/
      assert_select "form[action='/admin/visitors/#{@session.id}/conversation'] button", text: 'Message'
    end
    assert_select "tr[data-session='#{@offline.id}']", 0
  end

  test 'Live rows for the refresh, and JSON' do
    get '/admin/visitors?rows=1'
    assert_response :success
    assert_no_match(/<html/, response.body)
    assert_select "tr[data-session='#{@session.id}'][data-total='1']"

    body = json(:get, '/admin/visitors')
    assert_equal [@session.id.to_s], body['data'].map { |s| s['id'] }
    assert_equal 1, body.dig('meta', 'total')
  end

  test 'a visitor with a conversation gets Open chat instead' do
    conversation = chat_conversation(@contact)
    get '/admin/visitors'
    assert_select "tr[data-session='#{@session.id}'] a[href='/admin/inbox?conversation=#{conversation.id}']", text: 'Open chat'
  end

  test 'Message starts the conversation, assigned to the admin, and opens it in the inbox' do
    post "/admin/visitors/#{@session.id}/conversation"
    conversation = ThreadTable.conversations.find_by!(contact_id: @contact.id)
    assert_redirected_to "/admin/inbox?conversation=#{conversation.id}"
    assert_equal [@admin.id, @session.id], [conversation.assignee_id, conversation.visitor_session_id]

    body = json(:post, "/admin/visitors/#{@session.id}/conversation")
    assert_equal conversation.id.to_s, body.dig('data', 'conversation_id'), 'the same conversation the second time'
    assert_equal 1, ThreadTable.conversations.where(contact_id: @contact.id).count
  end

  test 'Carts: active ones changed within the hour, abandoned ones with an email idle an hour or more' do
    stale = chat_cart(email: 'gone@example.com')
    stale.update_columns(updated_at: 3.hours.ago)
    guest = chat_cart(email: nil)
    guest.update_columns(updated_at: 3.hours.ago)

    get '/admin/visitors/carts'
    assert_response :success
    assert_select '.nav-tabs a.nav-link.active', text: 'Carts'
    assert_select "a[href='/admin/orders/#{@cart.number}/cart']", text: @cart.number
    assert_select "a[href='/admin/orders/#{stale.number}/cart']", 0
    assert_select 'td', text: /× 2/

    get '/admin/visitors/carts?status=abandoned'
    assert_select "a[href='/admin/orders/#{stale.number}/cart']", text: stale.number
    assert_select "a[href='/admin/orders/#{@cart.number}/cart']", 0
    assert_select "a[href='/admin/orders/#{guest.number}/cart']", 0, 'a cart without an email is not abandoned'

    body = json(:get, '/admin/visitors/carts?status=abandoned')
    assert_equal [stale.number], body['data'].map { |c| c['number'] }
    assert body['data'].first['abandoned']
  end

  test 'a visit shows its pages, newest first, and its cart' do
    get "/admin/visitors/#{@session.id}"
    assert_response :success
    assert_select '.visitors__timeline li', 2
    assert_select '.visitors__timeline li:first-child', text: /Blue mug/
    assert_select '.visitors__cart li', text: /× 2/
    assert_select "form[action='/admin/visitors/#{@session.id}/conversation']"

    body = json(:get, "/admin/visitors/#{@session.id}")
    assert_equal %w[Blue\ mug Home], body.dig('data', 'pages').map { |p| p['title'] }

    json(:get, '/admin/visitors/0')
    assert_response :not_found
  end

  test 'non-admins are refused' do
    user = Spree.user_class.create!(email: 'shopper@example.com', password: 'password123')
    login_as(user, scope: :spree_user)

    get '/admin/visitors'
    assert_redirected_to '/forbidden'
    get '/admin/visitors/carts'
    assert_redirected_to '/forbidden'
    json(:get, '/admin/visitors')
    assert_response :forbidden
    post "/admin/visitors/#{@session.id}/conversation", headers: { 'ACCEPT' => 'application/json' }
    assert_response :forbidden
    assert_equal 0, ThreadTable.conversations.where(contact_id: @contact.id).count
  end
end
