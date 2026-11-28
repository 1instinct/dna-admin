require 'test_helper'

# rake chat:backfill (Chat::Backfill): older contacts, threads and messages get the chat columns.
class Chat::BackfillTest < ActiveSupport::TestCase
  include ChatTestHelper

  setup do
    @admin = chat_admin
    @user = create(:user)
    @contact = Contact.create!(full_name: 'Robin Customer', email: 'robin@example.com')
    @contact.update_columns(actor_id: @user.id, user_id: nil)
    @thread = ThreadTable.create!(archived: false, stale: false)
    @first = Message.create!(sender: @contact, receiver: @admin, thread_table: @thread, message: 'Has my order shipped?')
    @first.update_columns(created_at: 2.days.ago)
    @reply = Message.create!(sender: @admin, receiver: @contact, thread_table: @thread, message: 'Yes')
    @reply.update_columns(created_at: 1.day.ago)
    @archived = ThreadTable.create!(archived: true, stale: true)
    Message.create!(sender: @contact, receiver: @admin, thread_table: @archived, message: 'Old one')
    # Two users talking (live stream chat): not a customer conversation.
    @live = ThreadTable.create!(archived: false, stale: false)
    @between_users = Message.create!(sender: @admin, receiver: @user, thread_table: @live, message: 'Welcome')
    ThreadTable.where(id: [@thread.id, @archived.id, @live.id]).update_all(contact_id: nil, last_message_at: nil, channel: nil)
    Message.update_all(direction: nil)
  end

  test 'fills user, direction, contact, status, channel and last message time' do
    counts = Chat::Backfill.run

    assert_equal @user.id, @contact.reload.user_id
    assert_equal 'inbound', @first.reload.direction
    assert_equal 'outbound', @reply.reload.direction
    assert_nil @between_users.reload.direction

    @thread.reload
    assert_equal [@contact.id, 'open', 'web'], [@thread.contact_id, @thread.status, @thread.channel]
    assert_in_delta 1.day.ago.to_f, @thread.last_message_at.to_f, 2
    assert_equal [@contact.id, 'closed'], [@archived.reload.contact_id, @archived.status]
    assert_nil @live.reload.contact_id
    assert @live.last_message_at.present?
    assert_equal 0, @thread.staff_unread_count
    assert_equal 1, counts[:contacts_user]
  end

  test 'is safe to run again and never overwrites what the chat set' do
    Chat::Backfill.run
    Chat::Conversations.reopen(@archived.reload)

    counts = Chat::Backfill.run

    assert_equal 'open', @archived.reload.status
    assert_equal [0, 0, 0, 0, 0], counts.values_at(:contacts_user, :messages_inbound, :messages_outbound, :threads_contact,
                                                   :threads_last_message_at)
  end

  test 'skips an actor who no longer exists' do
    @contact.update_columns(actor_id: 999_999_999, user_id: nil)

    Chat::Backfill.run

    assert_nil @contact.reload.user_id
  end

  test 'the rake task runs it' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('chat:backfill')
    out, = capture_io { Rake::Task['chat:backfill'].execute }

    assert_match(/chat:backfill contacts_user=1/, out)
    assert_equal @contact.id, @thread.reload.contact_id
  end
end
