require 'test_helper'

# The storefront widget's API: POST visits and the customer chat under /api/v1/storefront.
class Spree::Api::V1::Storefront::ChatAndVisitsTest < ActionDispatch::IntegrationTest
  include ChatTestHelper

  BASE = '/api/v1/storefront'.freeze

  setup do
    Chat.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    Chat.config.storefront_url = 'https://shop.example.com'
    @token = Contact.generate_visitor_token
    @admin = chat_admin
  end

  teardown do
    Chat.reset_config!
  end

  def json
    JSON.parse(response.body)
  end

  def headers_for(token = @token, extra = {})
    { 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '203.0.113.9' }
      .merge(token ? { 'X-Visitor-Token' => token } : {}).merge(extra)
  end

  # A body given as a bare hash literal arrives in rest on Ruby 2.7.
  def api(method, path, body = nil, token: @token, headers: {}, **rest)
    body ||= rest.presence
    send(method, "#{BASE}#{path}", params: body&.to_json, headers: headers_for(token, headers))
    response.body.empty? ? {} : json
  end

  def send_message(body = 'Is this in stock?', token: @token, **extra)
    api(:post, '/chat/messages', { body: body }.merge(extra), token: token)
  end

  # --- visits ----------------------------------------------------------------------------------

  test 'a visit makes the contact and session and returns their tokens' do
    body = api(:post, '/visits', { url: 'https://shop.example.com/p/mug', title: 'Mug', referrer: 'https://ref.example.org',
                                   utm: { source: 'news' } }, headers: { 'CF-IPCountry' => 'SE', 'HTTP_USER_AGENT' => 'iPhone Mobile' })

    assert_response :success
    assert_equal @token, body['visitor_token']
    contact = Contact.find_by!(visitor_token: @token)
    session = contact.visitor_sessions.first
    assert_equal session.token, body['session_id']
    assert_equal ['https://shop.example.com/p/mug', 'news', 'SE', 'mobile', '203.0.113.0'],
                 [session.current_url, session.utm_source, session.country, session.device, session.ip]
  end

  test 'a visit without a token issues one; a malformed one is refused' do
    body = api(:post, '/visits', { url: '/' }, token: nil)
    assert_response :success
    assert Contact.valid_visitor_token?(body['visitor_token'])
    assert Contact.exists?(visitor_token: body['visitor_token'])

    api(:post, '/visits', { url: '/' }, token: 'bad token')
    assert_response :unauthorized
    assert_equal 'invalid visitor token', json['error']
  end

  test 'a visit needs a url and links the cart from its order token' do
    api(:post, '/visits', { title: 'No url' })
    assert_response :unprocessable_entity
    assert_equal({ 'url' => ["can't be blank"] }, json['fields'])

    cart = chat_cart
    api(:post, '/visits', { url: '/cart', order_token: cart.token })
    assert_response :success
    assert_equal cart, Contact.find_by!(visitor_token: @token).visitor_sessions.first.order
  end

  test 'a signed-in customer is linked to the contact; a bad Spree token is just anonymous' do
    user = create(:user)
    user.generate_spree_api_key!

    api(:post, '/visits', { url: '/' }, headers: { 'X-Spree-Token' => user.spree_api_key })
    contact = Contact.find_by!(visitor_token: @token)
    assert_equal [user.id, user.email], [contact.user_id, contact.email]

    other = Contact.generate_visitor_token
    api(:post, '/visits', { url: '/' }, token: other, headers: { 'X-Spree-Token' => 'wrong' })
    assert_response :success
    assert_nil Contact.find_by!(visitor_token: other).user_id
  end

  test 'a token the widget made is accepted when well formed (20 to 64 URL-safe characters)' do
    made = 'aB3_-' * 4
    body = api(:post, '/visits', { url: '/' }, token: made)
    assert_response :success
    assert_equal made, body['visitor_token']

    api(:get, '/chat', token: 'a' * 19)
    assert_response :unauthorized
    api(:get, '/chat', token: 'a' * 65)
    assert_response :unauthorized
  end

  test 'GET chat with an unknown token makes nothing, and shows a conversation staff started' do
    api(:get, '/chat')
    refute Contact.exists?(visitor_token: @token)

    api(:post, '/visits', { url: '/p/mug' })
    session = Contact.find_by!(visitor_token: @token).visitor_sessions.first
    id = Visitors::Adapter.new.start_conversation(session, @admin)[:conversation_id]
    Chat::InboxAdapter.new.reply(id, @admin, body: 'Can I help?', attachments: [], note: false)

    body = api(:get, '/chat')
    assert_equal [id, 1], body['conversation'].values_at('id', 'unread')
    assert_equal ['Can I help?'], api(:get, '/chat/messages')['messages'].map { |m| m['body'] }
  end

  test 'a signed-in customer’s current cart is found without an order token' do
    user = create(:user)
    user.generate_spree_api_key!
    cart = chat_cart(user: user)

    api(:post, '/visits', { url: '/' }, headers: { 'X-Spree-Token' => user.spree_api_key })

    assert_equal cart, Contact.find_by!(visitor_token: @token).visitor_sessions.first.order
  end

  test 'a bearer token links the user too' do
    user = create(:user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: '')
    token = record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token

    api(:post, '/visits', { url: '/' }, headers: { 'Authorization' => "Bearer #{token}" })

    assert_equal user.id, Contact.find_by!(visitor_token: @token).user_id
  end

  test 'a browser token another account owns is not handed to the next person who signs in' do
    first = create(:user)
    second = create(:user)
    second.generate_spree_api_key!
    shared = Contact.create!(visitor_token: @token, user: first, email: first.email)
    chat_conversation(shared, body: 'First person’s question')

    body = api(:post, '/visits', { url: '/' }, headers: { 'X-Spree-Token' => second.spree_api_key })
    refute_equal @token, body['visitor_token']
    mine = Contact.find_by!(visitor_token: body['visitor_token'])
    assert_equal second.id, mine.user_id

    chat = api(:get, '/chat', headers: { 'X-Spree-Token' => second.spree_api_key })
    assert_nil chat['conversation']
    assert_equal body['visitor_token'], chat['visitor_token']
  end

  # --- chat --------------------------------------------------------------------------------------

  test 'GET chat before any message: no conversation, the greeting and whether staff are online' do
    Chat.config.greeting = 'Hello there'

    body = api(:get, '/chat', token: nil)

    assert_response :success
    assert_equal({ 'visitor_token' => nil, 'conversation' => nil, 'greeting' => 'Hello there', 'online' => false }, body)
  end

  test 'the first message makes the contact and conversation, saves name and email, and returns the message' do
    body = send_message('Is this in stock?', name: 'Ada', email: 'ada@example.com')

    assert_response :created
    assert_equal @token, body['visitor_token']
    assert_equal({ 'id' => body.dig('conversation', 'id'), 'status' => 'open', 'unread' => 0 },
                 body['conversation'].slice('id', 'status', 'unread'))
    message = body['message']
    assert_equal ['inbound', 'Is this in stock?', { 'kind' => 'customer', 'name' => 'Ada' }, []],
                 message.values_at('direction', 'body', 'author', 'attachments')
    contact = Contact.find_by!(visitor_token: @token)
    assert_equal ['Ada', 'ada@example.com', true], [contact.name, contact.email, contact.email_opt_in]
    conversation = ThreadTable.find(body.dig('conversation', 'id'))
    assert_equal [contact.id, 'web', 1], [conversation.contact_id, conversation.channel, conversation.staff_unread_count]

    second = send_message('Hello?')
    assert_equal body.dig('conversation', 'id'), second.dig('conversation', 'id')
  end

  test 'a first message without a token still works and issues one' do
    body = send_message('Hi', token: nil)

    assert_response :created
    assert Contact.valid_visitor_token?(body['visitor_token'])
  end

  test 'a customer message links the live visitor session and pushes to the admin app' do
    api(:post, '/visits', { url: '/p/mug' })
    capturing_inbox_pushes do |calls|
      body = send_message('About this mug')

      assert_equal 1, calls.size
      assert_equal body.dig('conversation', 'id'), calls.first.first[:id]
      session = Contact.find_by!(visitor_token: @token).visitor_sessions.first
      assert_equal session.id, ThreadTable.find(body.dig('conversation', 'id')).visitor_session_id
    end
  end

  test 'message bodies are 1 to 4000 characters, and the email must be valid' do
    send_message('   ')
    assert_response :unprocessable_entity
    assert_equal 'body must be 1 to 4000 characters', json['error']

    send_message('x' * 4001)
    assert_response :unprocessable_entity

    send_message('Hi', email: 'not an email')
    assert_response :unprocessable_entity
    assert_equal({ 'email' => ['is not a valid email'] }, json['fields'])

    send_message({ 'nested' => 'object' })
    assert_response :unprocessable_entity
    refute Contact.exists?(visitor_token: @token), 'nothing is made for a refused message'
  end

  test 'staff replies come back oldest first, notes never do, and polling uses after' do
    first = send_message('Question')
    conversation = ThreadTable.find(first.dig('conversation', 'id'))
    reply = Chat::Conversations.post_outbound(conversation, @admin, body: 'Answer')
    Chat::Conversations.note(conversation, @admin, body: 'SECRET NOTE: refund risk')

    body = api(:get, '/chat/messages')
    assert_response :success
    assert_equal %w[Question Answer], body['messages'].map { |m| m['body'] }
    assert_equal({ 'kind' => 'staff', 'name' => Chat.staff_display_name }, body['messages'].last['author'])
    refute_includes response.body, 'SECRET NOTE'
    refute_includes response.body, @admin.email
    assert_equal 'delivered', reply.reload.delivery_status

    after = api(:get, "/chat/messages?after=#{body['messages'].last['id']}")
    assert_equal [], after['messages']
    later = Chat::Conversations.post_outbound(conversation, @admin, body: 'One more')
    assert_equal [later.id.to_s], api(:get, "/chat/messages?after=#{reply.id}")['messages'].map { |m| m['id'] }

    %w[/chat /chat/messages].each do |path|
      api(:get, path)
      refute_includes response.body, 'SECRET NOTE', "#{path} leaks a note"
    end
    api(:post, '/chat/read')
    refute_includes response.body, 'SECRET NOTE'
  end

  test 'GET chat shows the open conversation with the customer unread count; read clears it' do
    first = send_message('Question')
    conversation = ThreadTable.find(first.dig('conversation', 'id'))
    Chat::Conversations.post_outbound(conversation, @admin, body: 'Answer')

    body = api(:get, '/chat')
    assert_equal [conversation.id.to_s, 1], body['conversation'].values_at('id', 'unread')

    read = api(:post, '/chat/read')
    assert_response :success
    assert_equal 0, read.dig('conversation', 'unread')
    assert conversation.messages.outbound.all? { |m| m.reload.read_at.present? }
  end

  test 'someone else’s token sees nothing of this conversation' do
    send_message('Private question')
    other = Contact.generate_visitor_token

    assert_nil api(:get, '/chat', token: other)['conversation']
    assert_equal [], api(:get, '/chat/messages', token: other)['messages']
    assert_nil api(:post, '/chat/read', token: other)['conversation']
  end

  test 'a token sends at most 20 messages a minute' do
    20.times { |i| send_message("Message #{i}") }
    assert_response :created

    send_message('One too many')
    assert_response :too_many_requests
    assert_equal 'Too many requests. Try again later.', json['error']
    assert_includes 1..60, response.headers['Retry-After'].to_i

    travel 61.seconds do
      send_message('A minute later')
      assert_response :created
    end
  end

  test 'an IP starts at most 5 conversations an hour; more messages in them are fine' do
    5.times { send_message('New here', token: Contact.generate_visitor_token) }
    assert_response :created

    send_message('Sixth new conversation', token: Contact.generate_visitor_token)
    assert_response :too_many_requests
    assert_includes 1..3600, response.headers['Retry-After'].to_i

    first_token = Contact.order(:id).where.not(visitor_token: nil).first.visitor_token
    send_message('Still in my conversation', token: first_token)
    assert_response :created
  end

  test 'every request counts toward the per-token and per-IP request limits' do
    Chat.config.rate_limits = Chat.config.rate_limits.merge(request: { limit: 2, window: 1.minute })
    2.times { api(:get, '/chat') }
    assert_response :success

    api(:get, '/chat')
    assert_response :too_many_requests
    api(:get, '/chat', token: Contact.generate_visitor_token)
    assert_response :success
  end

  test 'resuming from the email link hands over the conversation and its contact' do
    first = send_message('Question', email: 'ada@example.com')
    conversation = ThreadTable.find(first.dig('conversation', 'id'))
    Chat::Conversations.post_outbound(conversation, @admin, body: 'Answer')
    Chat::Conversations.note(conversation, @admin, body: 'SECRET NOTE')
    token = Chat.resume_token(conversation)

    body = api(:get, "/chat/resume?token=#{CGI.escape(token)}", token: nil)

    assert_response :success
    assert_equal @token, body['visitor_token']
    assert_equal conversation.id.to_s, body.dig('conversation', 'id')
    assert_equal %w[Question Answer], body['messages'].map { |m| m['body'] }
    assert body.key?('greeting') && body.key?('online')
    refute_includes response.body, 'SECRET NOTE'

    api(:get, "/chat/resume?token=#{CGI.escape(token)}x", token: nil)
    assert_response :not_found
    assert_equal 'This link is invalid or has expired.', json['error']
  end

  test 'resume is limited per IP' do
    Chat.config.rate_limits = Chat.config.rate_limits.merge(resume: { limit: 2, window: 10.minutes })
    2.times { api(:get, '/chat/resume?token=nope', token: nil) }
    assert_response :not_found

    api(:get, '/chat/resume?token=nope', token: nil)
    assert_response :too_many_requests
    assert response.headers['Retry-After'].to_i.positive?
  end

  test 'responses are JSON with CORS like the rest of the API' do
    origin = ENV['ALLOWED_ORIGINS'].to_s.split(',').first || 'https://dna-admin-staging.instinct.is'
    process(:options, "#{BASE}/chat/messages", headers: { 'Origin' => origin, 'Access-Control-Request-Method' => 'POST',
                                                          'Access-Control-Request-Headers' => 'content-type,x-visitor-token' })

    assert_equal origin, response.headers['Access-Control-Allow-Origin']
    assert_match(/x-visitor-token/i, response.headers['Access-Control-Allow-Headers'].to_s)
    process(:options, "#{BASE}/chat", headers: { 'Origin' => origin, 'Access-Control-Request-Method' => 'GET',
                                                 'Access-Control-Request-Headers' => 'authorization,x-visitor-token' })
    assert_match(/authorization/i, response.headers['Access-Control-Allow-Headers'].to_s)

    get "#{BASE}/chat", headers: headers_for.merge('Origin' => origin)
    assert_equal origin, response.headers['Access-Control-Allow-Origin']
    assert_match(/Retry-After/i, response.headers['Access-Control-Expose-Headers'].to_s)

    api(:get, '/chat')
    assert_match %r{application/json}, response.headers['Content-Type']
  end
end
