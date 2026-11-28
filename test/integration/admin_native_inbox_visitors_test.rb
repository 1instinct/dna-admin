require 'test_helper'

# The admin app's inbox, visitors and carts through companion gem 0.7's endpoints, over this
# app's adapters (Chat::InboxAdapter, Visitors::Adapter).
class AdminNativeInboxVisitorsTest < ActionDispatch::IntegrationTest
  include ChatTestHelper
  include ActiveJob::TestHelper

  BASE = '/api/admin_native/v1'.freeze

  setup do
    @admin = chat_admin(email: 'staff@example.com')
    @admin.generate_spree_api_key!
    @contact = chat_contact
    @conversation = chat_conversation(@contact, body: 'Is this in stock?')
  end

  def call(method, path, body = nil)
    send(method, "#{BASE}#{path}", params: body&.to_json,
                                   headers: { 'X-Spree-Token' => @admin.spree_api_key, 'CONTENT_TYPE' => 'application/json' })
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  test 'the store announces inbox, visitors and carts' do
    capabilities = call(:get, '/capabilities')['capabilities']

    assert_includes capabilities, 'inbox'
    assert_includes capabilities, 'visitors'
    assert_includes capabilities, 'carts'
  end

  test 'conversations list, filters and one conversation with its customer context' do
    body = call(:get, '/inbox/conversations')
    assert_response :success
    assert_equal [@conversation.id.to_s], body['data'].map { |c| c['id'] }
    assert_equal 1, body.dig('meta', 'total_count')
    assert_equal ['Ada Example', 1, 'Is this in stock?'],
                 [body['data'].first.dig('customer', 'name'), body['data'].first['unread'], body['data'].first.dig('last_message', 'body')]

    assert_empty call(:get, '/inbox/conversations?assignee=me')['data']
    assert_equal 1, call(:get, '/inbox/conversations?q=stock&status=all')['data'].size
    assert_empty call(:get, "/inbox/conversations?updated_since=#{CGI.escape(1.minute.from_now.iso8601)}")['data']
    call(:get, '/inbox/conversations?status=pending')
    assert_response :unprocessable_entity

    one = call(:get, "/inbox/conversations/#{@conversation.id}")
    assert_response :success
    assert_equal({ 'id' => @contact.id.to_s, 'name' => 'Ada Example', 'email' => 'ada@example.com', 'phone' => nil },
                 one.dig('data', 'customer_context', 'contact'))
    call(:get, '/inbox/conversations/0')
    assert_response :not_found
  end

  test 'messages, a reply, a note, read, update and summary' do
    reply = call(:post, "/inbox/conversations/#{@conversation.id}/messages", { body: 'Yes, in blue' })
    assert_response :created
    assert_equal %w[outbound sent], reply['data'].values_at('direction', 'delivery')
    note = call(:post, "/inbox/conversations/#{@conversation.id}/messages", { body: 'VIP', note: true })
    assert_equal 'note', note.dig('data', 'direction')

    list = call(:get, "/inbox/conversations/#{@conversation.id}/messages")
    assert_equal ['Is this in stock?', 'Yes, in blue', 'VIP'], list['data'].map { |m| m['body'] }

    call(:post, "/inbox/conversations/#{@conversation.id}/messages", { body: '' })
    assert_response :unprocessable_entity

    read = call(:post, "/inbox/conversations/#{@conversation.id}/read")
    assert_equal 0, read.dig('data', 'unread')

    until_time = 2.hours.from_now.utc.change(usec: 0)
    updated = call(:patch, "/inbox/conversations/#{@conversation.id}", { assignee_id: @admin.id.to_s, snoozed_until: until_time.iso8601 })
    assert_response :success
    assert_equal ['snoozed', @admin.id.to_s, until_time.iso8601], [updated.dig('data', 'status'), updated.dig('data', 'assignee', 'id'),
                                                                  updated.dig('data', 'snoozed_until')]
    closed = call(:patch, "/inbox/conversations/#{@conversation.id}", { status: 'closed' })
    assert_equal 'closed', closed.dig('data', 'status')

    mine = call(:patch, "/inbox/conversations/#{@conversation.id}", { assignee_id: 'me' })
    assert_equal @admin.id.to_s, mine.dig('data', 'assignee', 'id'), "the app's Assign to me"

    summary = call(:get, '/inbox/summary')
    assert_equal({ 'open' => 0, 'unassigned' => 0, 'unread' => 0 }, summary['data'].slice('open', 'unassigned', 'unread'))
  end

  test 'a reply with an uploaded photo' do
    blob = media_blob(ShopMediaTestHelper::PNG_BYTES, 'photo.png', 'image/png')

    body = call(:post, "/inbox/conversations/#{@conversation.id}/messages", { body: '', attachments: [blob.signed_id] })

    assert_response :created
    assert_equal 'photo.png', body.dig('data', 'attachments', 0, 'filename')
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/}, body.dig('data', 'attachments', 0, 'url')
  end

  test 'visitors list, one visitor with pages, and starting a conversation' do
    cart = chat_cart
    stranger = chat_contact(visitor_token: Contact.generate_visitor_token, email: 'b@example.com', name: 'Ben')
    session = Visitors::Tracker.new(stranger, user_agent: 'iPhone Mobile').ping(url: '/p/mug', title: 'Mug', order_token: cart.token)

    list = call(:get, '/visitors?online=true')
    assert_response :success
    assert_equal [session.id.to_s], list['data'].map { |s| s['id'] }
    assert_equal [true, 'mobile', cart.number], [list['data'].first['online'], list['data'].first['device'],
                                                 list['data'].first.dig('cart', 'order_number')]

    one = call(:get, "/visitors/#{session.id}")
    assert_equal ['/p/mug'], one.dig('data', 'pages').map { |p| p['url'] }

    started = call(:post, "/visitors/#{session.id}/conversation")
    assert_response :success
    conversation = ThreadTable.find(started.dig('data', 'conversation_id'))
    assert_equal [stranger.id, @admin.id], [conversation.contact_id, conversation.assignee_id]

    summary = call(:get, '/summary')
    assert_equal 1, summary['visitors_online']
  end

  test 'carts come from Spree, built in' do
    cart = chat_cart

    body = call(:get, '/carts')

    assert_response :success
    assert_includes body['data'].map { |c| c['number'] }, cart.number
  end
end
