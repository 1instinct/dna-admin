require 'test_helper'

# The Rails admin's inbox (/admin/inbox, Spree::Admin::InboxController over Chat::InboxAdapter):
# the page, list filters, messages after an id, replies, notes (never shown to the customer),
# read, assign, snooze, close and reopen, and admin-only JSON endpoints.
class Spree::Admin::InboxControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ChatTestHelper

  setup do
    Chat.config.time_zone = 'UTC'
    @admin = chat_admin(email: 'inbox-admin@example.com')
    @teammate = chat_admin(email: 'teammate@example.com')
    login_as(@admin, scope: :spree_user)
    @contact = chat_contact(name: 'Ada Example', email: 'ada@example.com')
    @conversation = chat_conversation(@contact, body: 'Is the blue mug in stock?')
  end

  teardown do
    Chat.reset_config!
    Warden.test_reset!
  end

  def json(method, path, body = nil, headers = {})
    send(method, path, params: body&.to_json,
                       headers: { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }.merge(headers))
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def other_conversation(name, email, body: 'Hello')
    chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, name: name, email: email), body: body)
  end

  def ids(body)
    body['data'].map { |c| c['id'] }
  end

  test 'the page has the three panes, the filters and the staff to assign' do
    get '/admin/inbox'
    assert_response :success
    assert_select '#inbox[data-initial=""]'
    assert_select '#inbox .inbox__filters button[data-filter]', 4
    assert_select '#inbox button[data-filter=open][aria-pressed=true]'
    assert_select '#inbox [role=log][aria-live=polite]'
    assert_select '#inbox label[for=inbox-composer-body]'
    assert_select '#inbox label[for=inbox-note-toggle]', text: /Internal note/
    staff = JSON.parse(css_select('#inbox').first['data-staff'])
    assert_equal %w[inbox-admin@example.com teammate@example.com], staff.map { |s| s['email'] }

    get "/admin/inbox?conversation=#{@conversation.id}"
    assert_select "#inbox[data-initial='#{@conversation.id}']"
  end

  test 'conversations: open, mine, unassigned and closed filters, search and updated_since' do
    mine = other_conversation('Ben', 'ben@example.com')
    Chat::Conversations.assign(mine, @admin)
    theirs = other_conversation('Cy', 'cy@example.com', body: 'Where is my parcel?')
    Chat::Conversations.assign(theirs, @teammate)
    closed = other_conversation('Dee', 'dee@example.com')
    Chat::Conversations.close(closed)

    body = json(:get, '/admin/inbox/conversations')
    assert_response :success
    assert_equal [theirs, mine, @conversation].map { |c| c.id.to_s }.sort, ids(body).sort
    assert_equal 3, body.dig('meta', 'total')
    assert body.dig('meta', 'now')

    assert_equal [mine.id.to_s], ids(json(:get, '/admin/inbox/conversations?filter=mine'))
    assert_equal [@conversation.id.to_s], ids(json(:get, '/admin/inbox/conversations?filter=unassigned'))
    assert_equal [closed.id.to_s], ids(json(:get, '/admin/inbox/conversations?filter=closed'))
    assert_equal [theirs.id.to_s], ids(json(:get, '/admin/inbox/conversations?q=parcel'))
    assert_equal [mine.id.to_s], ids(json(:get, '/admin/inbox/conversations?q=ben%40example'))

    since = body.dig('meta', 'now')
    travel 1.second do
      Chat::Conversations.post_inbound(mine, body: 'Any news?')
      changed = json(:get, "/admin/inbox/conversations?updated_since=#{CGI.escape(since)}")
      assert_equal [mine.id.to_s], ids(changed)
      assert_equal 'Any news?', changed['data'].first.dig('last_message', 'body')
    end

    json(:get, '/admin/inbox/conversations?filter=pending')
    assert_response :unprocessable_entity
  end

  test 'a conversation comes with its customer context' do
    order = completed_order(email: 'ada@example.com')
    body = json(:get, "/admin/inbox/conversations/#{@conversation.id}")
    assert_response :success
    assert_equal 'Ada Example', body.dig('data', 'customer', 'name')
    assert_equal 1, body.dig('data', 'unread')
    assert_equal @contact.id.to_s, body.dig('customer_context', 'contact', 'id')
    assert_equal [order.number], body.dig('customer_context', 'recent_orders').map { |o| o['number'] }

    json(:get, "/admin/inbox/conversations/#{ThreadTable.create!(archived: false).id}")
    assert_response :not_found
  end

  test 'messages: oldest first, notes included, and only those after an id when polling' do
    first = @conversation.messages.first
    reply = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Yes, 4 left.')
    note = Chat::Conversations.note(@conversation, @admin, body: 'VIP, offer free shipping')

    body = json(:get, "/admin/inbox/conversations/#{@conversation.id}/messages")
    assert_response :success
    assert_equal [first, reply, note].map { |m| m.id.to_s }, ids(body)
    assert_equal %w[inbound outbound note], body['data'].map { |m| m['direction'] }

    body = json(:get, "/admin/inbox/conversations/#{@conversation.id}/messages?after=#{reply.id}")
    assert_equal [note.id.to_s], ids(body)
    body = json(:get, "/admin/inbox/conversations/#{@conversation.id}/messages?before=#{reply.id}")
    assert_equal [first.id.to_s], ids(body)
  end

  test 'reply goes to the customer and counts unread for them' do
    body = json(:post, "/admin/inbox/conversations/#{@conversation.id}/messages", { body: 'It is!' })
    assert_response :created
    assert_equal %w[outbound It\ is!], body['data'].values_at('direction', 'body')
    assert_equal 'inbox-admin@example.com', body.dig('data', 'author', 'name')
    assert_equal 'It is!', body.dig('conversation', 'last_message', 'body')
    assert_equal 1, @conversation.reload.customer_unread_count

    json(:post, "/admin/inbox/conversations/#{@conversation.id}/messages", { body: '   ' })
    assert_response :unprocessable_entity
  end

  test 'a reply can carry attachments' do
    file = Rack::Test::UploadedFile.new(StringIO.new(ShopMediaTestHelper::PNG_BYTES), 'image/png', true, original_filename: 'label.png')
    post "/admin/inbox/conversations/#{@conversation.id}/messages", params: { body: '', attachments: [file] }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal ['label.png'], body.dig('data', 'attachments').map { |a| a['filename'] }
    assert @conversation.messages.outbound.last.attachments.attached?
  end

  test 'notes stay with staff and never reach the storefront chat API' do
    body = json(:post, "/admin/inbox/conversations/#{@conversation.id}/messages", { body: 'Refund approved by finance', note: true })
    assert_response :created
    assert_equal 'note', body.dig('data', 'direction')
    assert_equal 0, @conversation.reload.customer_unread_count
    json(:post, "/admin/inbox/conversations/#{@conversation.id}/messages", { body: 'Your refund is on its way.' })

    logout(:spree_user)
    get '/api/v1/storefront/chat/messages', headers: { 'X-Visitor-Token' => @contact.visitor_token, 'ACCEPT' => 'application/json' }
    assert_response :success
    messages = JSON.parse(response.body)['messages']
    assert_equal ['Is the blue mug in stock?', 'Your refund is on its way.'], messages.map { |m| m['body'] }
    refute_includes response.body, 'finance'
    refute_includes response.body, 'inbox-admin@example.com'
  end

  test 'read marks the customer messages read for staff' do
    body = json(:post, "/admin/inbox/conversations/#{@conversation.id}/read")
    assert_response :success
    assert_equal 0, body.dig('data', 'unread')
    assert_equal 0, @conversation.reload.staff_unread_count
    assert @conversation.messages.inbound.all?(&:read_at)
  end

  test 'assign to me, to a teammate and back to nobody' do
    body = json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { assignee_id: 'me' })
    assert_response :success
    assert_equal @admin.id.to_s, body.dig('data', 'assignee', 'id')

    json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { assignee_id: @teammate.id })
    assert_equal @teammate.id, @conversation.reload.assignee_id

    json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { assignee_id: '' })
    assert_nil @conversation.reload.assignee_id

    shopper = Spree.user_class.create!(email: 'shopper@example.com', password: 'password123')
    json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { assignee_id: shopper.id })
    assert_response :unprocessable_entity
    assert_nil @conversation.reload.assignee_id
  end

  test 'snooze presets in the store time zone' do
    Chat.config.time_zone = 'America/New_York'
    # Wednesday 2026-12-02 15:00 in New York.
    travel_to Time.utc(2026, 12, 2, 20, 0, 0) do
      json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { snooze: '1h' })
      assert_response :success
      assert_equal ['snoozed', Time.utc(2026, 12, 2, 21)], [@conversation.reload.status, @conversation.snoozed_until]

      json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { snooze: 'tomorrow' })
      assert_equal Time.utc(2026, 12, 3, 14), @conversation.reload.snoozed_until, 'tomorrow 9:00 in New York'

      json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { snooze: 'monday' })
      assert_equal Time.utc(2026, 12, 7, 14), @conversation.reload.snoozed_until, 'next Monday 9:00 in New York'

      json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { snooze: 'someday' })
      assert_response :unprocessable_entity
    end
  end

  test 'close and reopen' do
    body = json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { status: 'closed' })
    assert_response :success
    assert_equal 'closed', body.dig('data', 'status')
    assert @conversation.reload.archived

    body = json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { status: 'open' })
    assert_equal 'open', body.dig('data', 'status')
    refute @conversation.reload.archived
  end

  test 'summary counts open, unassigned and unread' do
    other_conversation('Ben', 'ben@example.com')
    body = json(:get, '/admin/inbox/summary')
    assert_response :success
    assert_equal({ 'open' => 2, 'unassigned' => 2, 'unread' => 2 }, body['data'].slice('open', 'unassigned', 'unread'))
    assert_equal @admin.id.to_s, body.dig('data', 'me', 'id')
  end

  test 'non-admins are refused, the JSON endpoints with a status' do
    user = Spree.user_class.create!(email: 'shopper@example.com', password: 'password123')
    login_as(user, scope: :spree_user)

    get '/admin/inbox'
    assert_redirected_to '/forbidden'
    json(:get, '/admin/inbox/conversations')
    assert_response :forbidden
    json(:get, "/admin/inbox/conversations/#{@conversation.id}/messages")
    assert_response :forbidden
    json(:post, "/admin/inbox/conversations/#{@conversation.id}/messages", { body: 'Hi' })
    assert_response :forbidden
    json(:patch, "/admin/inbox/conversations/#{@conversation.id}", { status: 'closed' })
    assert_response :forbidden
    assert_equal 1, @conversation.messages.count
    assert_equal 'open', @conversation.reload.status

    logout(:spree_user)
    json(:get, '/admin/inbox/summary')
    assert_response :unauthorized
  end
end
