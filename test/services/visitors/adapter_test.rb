require 'test_helper'

# Visitors::Adapter: the admin app's visitors (spec §3) over this app's sessions.
class Visitors::AdapterTest < ActiveSupport::TestCase
  include ChatTestHelper

  SESSION_KEYS = %i[id contact user_id current_url current_title referrer utm device country started_at last_seen_at online
                    page_views cart conversation_id].freeze

  setup do
    @adapter = Visitors::Adapter.new
    @admin = chat_admin
    @user = create(:user)
    @contact = chat_contact(user: @user)
    @tracker = Visitors::Tracker.new(@contact, user_agent: 'iPhone Mobile', ip: '203.0.113.7', country: 'DE')
  end

  test 'it is the gem’s visitors adapter, available over the visitor tables' do
    assert @adapter.available?
    assert_equal SpreeAdminNative::Visitors::Adapter, Visitors::Adapter.superclass
    assert_equal 'Visitors::Adapter', SpreeAdminNative.config.visitors_adapter
    %i[available? sessions session start_conversation].each { |name| assert_respond_to @adapter, name }
  end

  test 'session shape, with cart and conversation' do
    cart = chat_cart
    @tracker.ping(url: '/p/mug', title: 'Mug', referrer: 'https://ref.example.org', utm: { source: 'news', medium: 'email' },
                  order_token: cart.token)
    conversation = chat_conversation(@contact)

    record = @adapter.sessions({})[:records].first

    assert_equal SESSION_KEYS.sort, record.keys.sort
    assert_equal({ id: @contact.id.to_s, name: 'Ada Example', email: 'ada@example.com' }, record[:contact])
    assert_equal [@user.id.to_s, '/p/mug', 'Mug', 'https://ref.example.org', 'mobile', 'DE', true, 1],
                 record.values_at(:user_id, :current_url, :current_title, :referrer, :device, :country, :online, :page_views)
    assert_equal({ source: 'news', medium: 'email', campaign: nil }, record[:utm])
    assert_equal({ order_number: cart.number, item_count: 2, total: '25.00', currency: 'USD' }, record[:cart])
    assert_equal conversation.id.to_s, record[:conversation_id]
    assert Time.iso8601(record[:started_at]) && Time.iso8601(record[:last_seen_at])
  end

  test 'sessions: online filter, newest first, paging' do
    online = @tracker.ping(url: '/now')
    other = chat_contact(visitor_token: Contact.generate_visitor_token, email: 'b@example.com')
    offline = Visitors::Tracker.new(other).ping(url: '/earlier', now: 10.minutes.ago)

    assert_equal [online.id.to_s, offline.id.to_s], @adapter.sessions({})[:records].map { |s| s[:id] }
    assert_equal [online.id.to_s], @adapter.sessions(online: 'true')[:records].map { |s| s[:id] }
    assert_equal [offline.id.to_s], @adapter.sessions('online' => false)[:records].map { |s| s[:id] }
    page = @adapter.sessions(page: 2, per_page: 1)
    assert_equal [2, [offline.id.to_s]], [page[:total], page[:records].map { |s| s[:id] }]

    record = @adapter.sessions({})[:records].last
    assert_equal [false, nil, nil, nil], record.values_at(:online, :utm, :cart, :conversation_id)
  end

  test 'session: one session with its last 50 pages, newest first' do
    session = @tracker.ping(url: '/a', title: 'A')
    52.times { |i| @tracker.ping(url: "/p#{i}", title: "P#{i}") }

    record = @adapter.session(session.id)

    assert_equal (SESSION_KEYS + [:pages]).sort, record.keys.sort
    assert_equal 50, record[:pages].size
    assert_equal({ url: '/p51', title: 'P51' }, record[:pages].first.slice(:url, :title))
    assert Time.iso8601(record[:pages].first[:at])
    assert_equal 53, record[:page_views]
    assert_nil @adapter.session(0)
    assert_equal session.id.to_s, @adapter.session({ id: session.id.to_s })[:id]
  end

  test 'start_conversation: starts one assigned to the staff member, or returns the open one' do
    session = @tracker.ping(url: '/p/mug')

    result = @adapter.start_conversation(@adapter.session(session.id), @admin)

    assert_equal %i[conversation_id], result.keys
    conversation = ThreadTable.find(result[:conversation_id])
    assert_equal [@contact.id, session.id, @admin.id, 'web'], [conversation.contact_id, conversation.visitor_session_id,
                                                              conversation.assignee_id, conversation.channel]
    assert_equal result, @adapter.start_conversation(session.id, chat_admin)
    assert_equal @admin.id, conversation.reload.assignee_id, 'starting again keeps the assignee'
    assert_raises(ActiveRecord::RecordNotFound) { @adapter.start_conversation(0, @admin) }
  end

  test 'staff replies to a started conversation reach the visitor’s widget' do
    session = @tracker.ping(url: '/p/mug')
    id = @adapter.start_conversation(session, @admin)[:conversation_id]

    Chat::InboxAdapter.new.reply(id, @admin, body: 'Can I help?', attachments: [], note: false)

    assert_equal ['Can I help?'], Chat::Conversations.current_for(@contact).messages.visible_to_customer.map(&:body)
  end
end
