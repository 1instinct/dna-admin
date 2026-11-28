require 'test_helper'
require 'minitest/mock'

# Chat::Conversations: the one place conversations change, with their counters and statuses.
class Chat::ConversationsTest < ActiveSupport::TestCase
  include ChatTestHelper
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  setup do
    @admin = chat_admin
    @contact = chat_contact
  end

  teardown { Chat.reset_config! }

  test 'find_or_create returns the current conversation and makes one only when there is none' do
    conversation, created = Chat::Conversations.find_or_create(@contact, channel: 'web')
    assert created
    assert_equal ['open', 'web', @contact.id], [conversation.status, conversation.channel, conversation.contact_id]

    again, created_again = Chat::Conversations.find_or_create(@contact)
    assert_equal conversation, again
    refute created_again

    Chat::Conversations.close(conversation)
    fresh, created_fresh = Chat::Conversations.find_or_create(@contact)
    assert created_fresh
    refute_equal conversation, fresh
  end

  test 'an inbound message counts unread for staff, reopens, and moves the conversation up' do
    conversation, = Chat::Conversations.find_or_create(@contact)
    Chat::Conversations.snooze(conversation, 1.day.from_now)

    message = Chat::Conversations.post_inbound(conversation, body: '  Is this in stock?  ')
    conversation.reload

    assert_equal ['inbound', 'Is this in stock?', 'web'], [message.direction, message.body, message.channel]
    assert_equal @contact, message.sender
    assert_equal conversation.id, message.thread_table_id
    assert_equal ['open', nil, false], [conversation.status, conversation.snoozed_until, conversation.archived]
    assert_equal 1, conversation.staff_unread_count
    assert_equal message.created_at.to_i, conversation.last_message_at.to_i
    assert @contact.reload.last_seen_at.present?

    Chat::Conversations.post_inbound(conversation, body: 'Hello?')
    assert_equal 2, conversation.reload.staff_unread_count
  end

  test 'a closed conversation reopens on a new customer message' do
    conversation = chat_conversation(@contact)
    Chat::Conversations.close(conversation)
    assert conversation.reload.archived

    Chat::Conversations.post_inbound(conversation, body: 'One more thing')

    assert_equal 'open', conversation.reload.status
  end

  test 'the admin app is told about each customer message' do
    conversation, = Chat::Conversations.find_or_create(@contact)
    capturing_inbox_pushes do |calls|
      Chat::Conversations.post_inbound(conversation, body: 'Ping')

      assert_equal 1, calls.size
      conversation_hash, message_hash = calls.first
      assert_equal conversation.id.to_s, conversation_hash[:id]
      assert_equal 'Ada Example', conversation_hash[:customer][:name]
      assert_equal 'Ping', conversation_hash[:last_message][:body]
      assert_equal ['inbound', 'Ping'], message_hash.values_at(:direction, :body)
    end
  end

  test 'the gem queues the push for paired devices' do
    SpreeAdminNative::Device.create!(owner: @admin, name: 'Phone', token_digest: SecureRandom.hex(16),
                                     push_token: 'ExponentPushToken[test]')
    conversation, = Chat::Conversations.find_or_create(@contact)

    assert_enqueued_jobs(1, only: SpreeAdminNative::PushJob) do
      Chat::Conversations.post_inbound(conversation, body: 'Push me')
    end
    assert_no_enqueued_jobs(only: SpreeAdminNative::PushJob) do
      Chat::Conversations.post_outbound(conversation, @admin, body: 'Replies are not pushed')
    end
  end

  test 'a failing push never loses the message' do
    conversation, = Chat::Conversations.find_or_create(@contact)
    SpreeAdminNative::Inbox.stub(:notify_inbound, ->(*) { raise 'Expo is down' }) do
      assert Chat::Conversations.post_inbound(conversation, body: 'Still saved').persisted?
    end
  end

  test 'a staff reply counts unread for the customer and is delivered on the channel' do
    conversation = chat_conversation(@contact)
    delivered = []
    Chat::Channels.stub(:deliver, ->(m) { delivered << m }) do
      message = Chat::Conversations.post_outbound(conversation, @admin, body: 'Yes, we have it')

      assert_equal ['outbound', @admin, @admin, @contact, 'sent'],
                   [message.direction, message.author, message.sender, message.receiver, message.delivery_status]
      assert_equal [message], delivered
    end
    conversation.reload
    assert_equal [1, 1], [conversation.customer_unread_count, conversation.staff_unread_count]
  end

  test 'a note changes no counter, is never delivered, and bumps updated_at only' do
    conversation = chat_conversation(@contact)
    conversation.update_columns(updated_at: 1.hour.ago)
    last_message_at = conversation.reload.last_message_at
    Chat::Channels.stub(:deliver, ->(_m) { flunk 'notes are never delivered' }) do
      note = Chat::Conversations.note(conversation, @admin, body: 'VIP customer')

      assert_equal ['note', @admin, nil], [note.direction, note.author, note.receiver]
    end
    conversation.reload
    assert_equal [1, 0], [conversation.staff_unread_count, conversation.customer_unread_count]
    assert_equal last_message_at.to_i, conversation.last_message_at.to_i
    assert conversation.updated_at > 1.minute.ago
  end

  test 'reading clears each side’s counter and stamps the messages' do
    conversation = chat_conversation(@contact)
    Chat::Conversations.post_inbound(conversation, body: 'Again')
    reply = Chat::Conversations.post_outbound(conversation, @admin, body: 'Hi')

    Chat::Conversations.mark_read_by_staff(conversation)
    conversation.reload
    assert_equal 0, conversation.staff_unread_count
    assert conversation.messages.inbound.all? { |m| m.read_at.present? && m.is_read }
    assert_nil reply.reload.read_at

    Chat::Conversations.mark_read_by_customer(conversation)
    assert_equal 0, conversation.reload.customer_unread_count
    assert_equal 'delivered', reply.reload.delivery_status
    assert reply.read_at.present?
  end

  test 'counters hold under concurrent writers' do
    conversation, = Chat::Conversations.find_or_create(@contact)
    # The row lock is what keeps these from losing increments; run them back to back on stale
    # copies, as two requests would hold them.
    copies = Array.new(3) { ThreadTable.find(conversation.id) }
    copies.each { |copy| Chat::Conversations.post_inbound(copy, body: 'Hi') }

    assert_equal 3, conversation.reload.staff_unread_count
  end

  test 'assign, snooze, close, reopen and update' do
    conversation = chat_conversation(@contact)

    Chat::Conversations.assign(conversation, @admin)
    assert_equal @admin, conversation.reload.assignee
    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.assign(conversation, create(:user)) }

    Chat::Conversations.snooze(conversation, 2.hours.from_now)
    assert_equal 'snoozed', conversation.reload.status
    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.snooze(conversation, 1.hour.ago) }

    Chat::Conversations.close(conversation)
    assert_equal ['closed', nil], [conversation.reload.status, conversation.snoozed_until]
    Chat::Conversations.reopen(conversation)
    assert_equal 'open', conversation.reload.status

    Chat::Conversations.update(conversation, 'assignee_id' => nil, 'snoozed_until' => 3.hours.from_now.iso8601)
    assert_equal ['snoozed', nil], [conversation.reload.status, conversation.assignee_id]
    Chat::Conversations.update(conversation, snoozed_until: nil)
    assert_equal 'open', conversation.reload.status, 'clearing the snooze wakes it'
    Chat::Conversations.update(conversation, status: 'open', assignee_id: @admin.id.to_s)
    assert_equal ['open', @admin.id], [conversation.reload.status, conversation.assignee_id]

    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.update(conversation, status: 'pending') }
    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.update(conversation, status: 'snoozed') }
    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.update(conversation, assignee_id: 999_999_999) }
    assert ArgumentError > Chat::Conversations::Invalid
  end

  test 'a body is 1 to 4000 characters' do
    conversation, = Chat::Conversations.find_or_create(@contact)

    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.post_inbound(conversation, body: '   ') }
    assert_raises(Chat::Conversations::Invalid) { Chat::Conversations.post_inbound(conversation, body: 'x' * 4001) }
    assert Chat::Conversations.post_inbound(conversation, body: 'x' * 4000).persisted?
  end

  test 'a reply with attachments may have no text' do
    conversation = chat_conversation(@contact)
    blob = media_blob(ShopMediaTestHelper::PNG_BYTES, 'photo.png', 'image/png')

    message = Chat::Conversations.post_outbound(conversation, @admin, body: '', attachments: [blob.signed_id])

    assert_equal ['', 1], [message.body, message.attachments.count]
  end

  test 'attachments are uploads by signed id' do
    conversation = chat_conversation(@contact)
    blob = media_blob(ShopMediaTestHelper::PNG_BYTES, 'photo.png', 'image/png')

    message = Chat::Conversations.post_outbound(conversation, @admin, body: 'See photo', attachments: [blob.signed_id])

    assert_equal ['photo.png'], message.attachments.map { |a| a.filename.to_s }
    assert_raises(Chat::Conversations::Invalid) do
      Chat::Conversations.post_outbound(conversation, @admin, body: 'Bad', attachments: ['nope'])
    end
  end

  test 'snoozed conversations wake when their time comes, and the counters see them' do
    due = chat_conversation(@contact)
    Chat::Conversations.snooze(due, 1.hour.from_now)
    due.update_columns(snoozed_until: 1.minute.ago)
    later = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'b@example.com'))
    Chat::Conversations.snooze(later, 1.hour.from_now)
    assigned = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'c@example.com'))
    Chat::Conversations.assign(assigned, @admin)
    Chat::Conversations.mark_read_by_staff(assigned)

    counters = Chat::Conversations.counters

    assert_equal 'open', due.reload.status
    assert_equal 'snoozed', later.reload.status
    assert_equal({ open: 2, unassigned: 1, unread: 2 }, counters)
  end
end
