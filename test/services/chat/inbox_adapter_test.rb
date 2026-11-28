require 'test_helper'

# Chat::InboxAdapter: the admin app's inbox (spec §2) over this app's conversations. Shapes are
# the contract with companion gem 0.7, which serializes and validates them.
class Chat::InboxAdapterTest < ActiveSupport::TestCase
  include ChatTestHelper

  CONVERSATION_KEYS = %i[id status channel subject customer assignee unread last_message updated_at snoozed_until].freeze
  CUSTOMER_KEYS = %i[name email avatar_url contact_id user_id].freeze
  MESSAGE_KEYS = %i[id direction body channel author attachments created_at read_at delivery].freeze
  CONTEXT_KEYS = %i[contact user session cart recent_orders].freeze

  setup do
    Chat.config.storefront_url = 'https://shop.example.com'
    @adapter = Chat::InboxAdapter.new
    @admin = chat_admin(email: 'staff@example.com')
    @other_admin = chat_admin
    @user = create(:user, email: 'ada@example.com')
    @contact = chat_contact(user: @user)
    @conversation = chat_conversation(@contact, body: 'Is this in stock?')
  end

  teardown { Chat.reset_config! }

  def iso?(value)
    value.is_a?(String) && Time.iso8601(value)
  rescue ArgumentError
    false
  end

  test 'it is the gem’s inbox adapter, available over the chat tables' do
    assert @adapter.available?
    assert_equal SpreeAdminNative::Inbox::Adapter, Chat::InboxAdapter.superclass
    assert_equal 'Chat::InboxAdapter', SpreeAdminNative.config.inbox_adapter
    %i[available? conversations conversation messages reply update mark_read summary customer_context].each do |name|
      assert_respond_to @adapter, name
    end
  end

  test 'conversation shape' do
    hash = @adapter.conversation(@conversation.id)

    assert_equal CONVERSATION_KEYS.sort, hash.keys.sort
    assert_equal [@conversation.id.to_s, 'open', 'web', nil, nil, 1], hash.values_at(:id, :status, :channel, :subject, :assignee, :unread)
    assert_equal CUSTOMER_KEYS.sort, hash[:customer].keys.sort
    assert_equal({ name: 'Ada Example', email: 'ada@example.com', avatar_url: nil, contact_id: @contact.id.to_s,
                   user_id: @user.id.to_s }, hash[:customer])
    assert_equal ['Is this in stock?', 'inbound'], hash[:last_message].values_at(:body, :direction)
    assert iso?(hash[:last_message][:at])
    assert iso?(hash[:updated_at])
    assert_nil hash[:snoozed_until]
    assert_nil @adapter.conversation(0)
    assert_nil @adapter.conversation(ThreadTable.create!(archived: false).id), 'a thread without a contact is not a conversation'

    Chat::Conversations.assign(@conversation, @admin)
    assert_equal({ id: @admin.id.to_s, email: 'staff@example.com' }, @adapter.conversation(@conversation.id.to_s)[:assignee])
  end

  test 'conversations: newest activity first, open by default, with a total' do
    older = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, name: 'Ben', email: 'ben@example.com'))
    older.update_columns(last_message_at: 1.day.ago)
    closed = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, name: 'Cy', email: 'cy@example.com'))
    Chat::Conversations.close(closed)
    ThreadTable.create!(archived: false) # not a conversation

    result = @adapter.conversations({})
    assert_equal %i[records total], result.keys.sort
    assert_equal 2, result[:total]
    assert_equal [@conversation.id.to_s, older.id.to_s], result[:records].map { |c| c[:id] }
    assert result[:records].all? { |c| c.keys.sort == CONVERSATION_KEYS.sort }

    assert_equal [closed.id.to_s], @adapter.conversations(status: 'closed')[:records].map { |c| c[:id] }
    assert_equal 3, @adapter.conversations('status' => 'all')[:total]
    Chat::Conversations.snooze(older, 1.hour.from_now)
    assert_equal [older.id.to_s], @adapter.conversations(status: 'snoozed')[:records].map { |c| c[:id] }
    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.conversations(status: 'pending') }
  end

  test 'conversations: assignee me, unassigned or any' do
    mine = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'm@example.com'))
    theirs = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 't@example.com'))
    Chat::Conversations.assign(mine, @admin)
    Chat::Conversations.assign(theirs, @other_admin)

    ids = ->(filters) { @adapter.conversations(filters)[:records].map { |c| c[:id].to_i }.sort }
    assert_equal [mine.id], ids.call(assignee: 'me', admin: @admin)
    assert_equal [theirs.id], ids.call(assignee: 'me', admin: @other_admin)
    assert_equal [@conversation.id], ids.call(assignee: 'unassigned', admin: @admin)
    assert_equal [@conversation.id, mine.id, theirs.id].sort, ids.call(assignee: 'any', admin: @admin)
    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.conversations(assignee: 'me') }
    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.conversations(assignee: 'someone') }
  end

  test 'conversations: q searches contact name, email and message text' do
    ben = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, name: 'Ben Bright', email: 'ben@example.org'),
                            body: 'Where is my parcel?')
    legacy = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, name: nil, full_name: 'Old Name',
                                            email: 'old@example.net'), body: 'Hello')

    ids = ->(q) { @adapter.conversations(q: q)[:records].map { |c| c[:id].to_i }.sort }
    assert_equal [ben.id], ids.call('bright')
    assert_equal [ben.id], ids.call('EXAMPLE.ORG')
    assert_equal [ben.id], ids.call('parcel')
    assert_equal [@conversation.id], ids.call('in stock')
    assert_equal [legacy.id], ids.call('old name')
    assert_equal [], ids.call('100%')
  end

  test 'conversations: updated_since returns only what changed, for polling' do
    @conversation.update_columns(updated_at: 1.hour.ago)
    fresh = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'f@example.com'))

    since = 10.minutes.ago.iso8601
    assert_equal [fresh.id.to_s], @adapter.conversations(updated_since: since)[:records].map { |c| c[:id] }
    assert_equal [fresh.id.to_s], @adapter.conversations(updated_since: 10.minutes.ago)[:records].map { |c| c[:id] }

    Chat::Conversations.note(@conversation, @admin, body: 'Seen')
    assert_equal 2, @adapter.conversations(updated_since: since)[:total]
    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.conversations(updated_since: 'yesterday-ish') }
  end

  test 'conversations: paging' do
    4.times { |i| chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: "p#{i}@example.com")) }

    first = @adapter.conversations(page: 1, per_page: 2)
    second = @adapter.conversations(page: '2', per_page: '2')
    third = @adapter.conversations(page: 3, per_page: 2)

    assert_equal [5, 2, 2, 1], [first[:total], first[:records].size, second[:records].size, third[:records].size]
    assert_empty first[:records].map { |c| c[:id] } & second[:records].map { |c| c[:id] }
  end

  test 'messages: oldest first, notes included, with after, before and limit' do
    reply = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Yes')
    note = Chat::Conversations.note(@conversation, @admin, body: 'VIP')
    blob = media_blob(ShopMediaTestHelper::PNG_BYTES, 'photo.png', 'image/png')
    photo = Chat::Conversations.post_inbound(@conversation, body: 'Photo', attachments: [blob.signed_id])

    list = @adapter.messages(@adapter.conversation(@conversation.id))
    assert_equal %w[Is\ this\ in\ stock? Yes VIP Photo], list.map { |m| m[:body] }
    assert list.all? { |m| m.keys.sort == MESSAGE_KEYS.sort }
    inbound, outbound, note_hash, with_photo = list
    assert_equal ['inbound', 'web', { kind: 'customer', name: 'Ada Example' }, nil], inbound.values_at(:direction, :channel, :author, :delivery)
    assert_equal ['outbound', { kind: 'staff', name: 'staff@example.com' }, 'sent'], outbound.values_at(:direction, :author, :delivery)
    assert_equal 'note', note_hash[:direction]
    assert_equal [{ filename: 'photo.png', content_type: 'image/png' }], with_photo[:attachments].map { |a| a.slice(:filename, :content_type) }
    assert_match %r{/rails/active_storage/blobs/}, with_photo[:attachments].first[:url]
    assert iso?(inbound[:created_at])

    assert_equal [note.id.to_s, photo.id.to_s], @adapter.messages(@conversation, after: reply.id).map { |m| m[:id] }
    assert_equal [reply.id.to_s], @adapter.messages(@conversation.id, before: note.id, limit: 1).map { |m| m[:id] }
    assert_equal [note.id.to_s, photo.id.to_s], @adapter.messages(@conversation, limit: 2).map { |m| m[:id] }
    assert_raises(ActiveRecord::RecordNotFound) { @adapter.messages(0) }
  end

  test 'reply: on the channel, or as a note' do
    message = @adapter.reply(@adapter.conversation(@conversation.id), @admin, body: 'On its way', attachments: [], note: false)
    assert_equal MESSAGE_KEYS.sort, message.keys.sort
    assert_equal ['outbound', 'On its way', 'sent'], message.values_at(:direction, :body, :delivery)
    assert_equal 1, @conversation.reload.customer_unread_count

    note = @adapter.reply(@conversation.id, @admin, body: 'Internal', attachments: nil, note: true)
    assert_equal 'note', note[:direction]
    assert_equal 1, @conversation.reload.customer_unread_count

    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.reply(@conversation.id, @admin, body: '', attachments: [], note: false) }
  end

  test 'update: status, assignee and snooze' do
    hash = @adapter.update(@conversation.id, @admin, { 'assignee_id' => @admin.id.to_s })
    assert_equal CONVERSATION_KEYS.sort, hash.keys.sort
    assert_equal @admin.id.to_s, hash[:assignee][:id]

    until_time = 2.hours.from_now.change(usec: 0)
    hash = @adapter.update(@conversation.id, @admin, { snoozed_until: until_time.iso8601 })
    assert_equal ['snoozed', until_time.utc.iso8601], hash.values_at(:status, :snoozed_until)

    hash = @adapter.update(@conversation.id, @admin, { status: 'closed', assignee_id: nil })
    assert_equal ['closed', nil, nil], hash.values_at(:status, :assignee, :snoozed_until)

    assert_raises(SpreeAdminNative::AdapterInvalid) { @adapter.update(@conversation.id, @admin, { status: 'nope' }) }
  end

  test 'mark_read and summary' do
    Chat::Conversations.post_inbound(@conversation, body: 'Hello?')
    assert_equal({ open: 1, unassigned: 1, unread: 1 }, @adapter.summary(@admin))

    hash = @adapter.mark_read(@conversation.id, @admin)
    assert_equal 0, hash[:unread]
    assert_equal({ open: 1, unassigned: 1, unread: 0 }, @adapter.summary(@admin))
  end

  test 'customer context: contact, user, live session, cart with images, recent orders' do
    cart = chat_cart(user: @user)
    session = @contact.visitor_sessions.create!(token: 'tok-ctx', started_at: 5.minutes.ago, last_seen_at: 30.seconds.ago,
                                                current_url: 'https://shop.example.com/p/mug', order: cart)
    @conversation.update!(visitor_session: session)
    completed_order(user: @user, completed_at: 2.days.ago)
    newest = completed_order(user: @user, completed_at: 1.day.ago)

    Chat::Current.set(base_url: 'https://admin.example.com') do
      context = @adapter.customer_context(@adapter.conversation(@conversation.id))

      assert_equal CONTEXT_KEYS.sort, context.keys.sort
      assert_equal({ id: @contact.id.to_s, name: 'Ada Example', email: 'ada@example.com', phone: nil }, context[:contact])
      assert_equal({ id: @user.id.to_s, email: 'ada@example.com' }, context[:user])
      assert_equal [session.id.to_s, 'https://shop.example.com/p/mug', true], context[:session].values_at(:id, :current_url, :online)
      assert iso?(context[:session][:last_seen_at])
      assert_equal [cart.number, 2, '25.00', 'USD'], context[:cart].values_at(:order_number, :item_count, :total, :currency)
      item = context[:cart][:items].first
      assert_equal 2, item[:quantity]
      assert_match(/\AMug /, item[:name])
      assert_match %r{\Ahttps://admin\.example\.com/rails/active_storage/}, item[:image_url]
      assert_equal 2, context[:recent_orders].size
      assert_equal [newest.number, 'complete', '40.00'], context[:recent_orders].first.values_at(:number, :state, :total)
    end
  end

  test 'customer context for a visitor with nothing yet' do
    contact = chat_contact(visitor_token: Contact.generate_visitor_token, email: nil, name: nil)
    conversation = chat_conversation(contact)

    assert_equal({ contact: { id: contact.id.to_s, name: nil, email: nil, phone: nil }, user: nil, session: nil, cart: nil,
                   recent_orders: [] }, @adapter.customer_context(conversation.id))
  end

  test 'recent orders by email when the contact has no account' do
    contact = chat_contact(visitor_token: Contact.generate_visitor_token, email: 'Guest@Example.com')
    order = completed_order(email: 'guest@example.com')

    assert_equal [order.number], @adapter.customer_context(chat_conversation(contact))[:recent_orders].map { |o| o[:number] }
  end
end
