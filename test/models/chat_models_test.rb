require 'test_helper'

# Contact, ThreadTable, Message and VisitorSession: the chat columns and the older behaviour kept.
class ChatModelsTest < ActiveSupport::TestCase
  include ChatTestHelper

  test 'a contact keeps user_id and actor_id in step, whichever is set' do
    user = create(:user)
    other = create(:user)

    by_actor = Contact.create!(full_name: 'Old Code', actor: user)
    assert_equal user.id, by_actor.user_id

    by_user = Contact.create!(name: 'New Code', user: user)
    assert_equal user.id, by_user.actor_id

    by_user.update!(actor_id: other.id)
    assert_equal other.id, by_user.reload.user_id
    by_user.update!(user_id: user.id)
    assert_equal user.id, by_user.reload.actor_id
  end

  test 'a contact needs no account, and its chat name fills a blank full_name' do
    contact = Contact.create!(name: 'Ada')

    assert_nil contact.user
    assert_equal 'Ada', contact.full_name
    assert_equal 'Ada', contact.display_name
    assert_equal 'kept', Contact.create!(name: 'Ada', full_name: 'kept').full_name
    assert_equal 'x@example.com', Contact.new(email: 'x@example.com').display_name
  end

  test 'visitor tokens are unique, well formed and generated' do
    token = Contact.generate_visitor_token
    assert Contact.valid_visitor_token?(token)
    Contact.create!(visitor_token: token)

    refute Contact.new(visitor_token: token).valid?
    refute Contact.new(visitor_token: 'short').valid?
    refute Contact.new(visitor_token: 'has spaces and is long enough!!').valid?
    refute Contact.valid_visitor_token?(nil)
    assert Contact.new(visitor_token: nil).valid?
  end

  test 'a changed email must be valid; an older invalid one does not block other changes' do
    refute Contact.new(email: 'not-an-email').valid?

    contact = Contact.create!(name: 'Old')
    contact.update_column(:email, 'legacy junk')
    assert contact.update(phone: '123')
  end

  test 'conversations are threads with a contact, with a known status' do
    contact = chat_contact
    conversation = ThreadTable.create!(contact: contact)
    plain = ThreadTable.create!(archived: false, stale: false)

    assert_equal 'open', conversation.status
    assert_equal [0, 0], [conversation.staff_unread_count, conversation.customer_unread_count]
    assert_includes ThreadTable.conversations, conversation
    refute_includes ThreadTable.conversations, plain
    refute ThreadTable.new(status: 'pending').valid?
    assert_includes contact.conversations, conversation
  end

  test 'messages take a direction, and notes are never visible to the customer' do
    thread = ThreadTable.create!(contact: chat_contact)
    inbound = thread.messages.create!(direction: 'inbound', message: 'Hi')
    note = thread.messages.create!(direction: 'note', message: 'VIP')
    legacy = thread.messages.create!(message: 'Older message')

    refute Message.new(direction: 'sideways').valid?
    refute Message.new(delivery_status: 'lost').valid?
    assert_equal [inbound, legacy].map(&:id).sort, thread.messages.visible_to_customer.pluck(:id).sort
    assert note.note?
    assert_equal 'Hi', inbound.body
  end

  test 'a message given a thread keeps it; one without still gets the older automatic thread' do
    contact = chat_contact
    admin = chat_admin
    thread = ThreadTable.create!(contact: contact)

    given = Message.create!(sender: contact, receiver: admin, message: 'In my thread', thread_table: thread)
    assert_equal thread.id, given.reload.thread_table_id

    # The older rule: the thread of the pair's last message within 7 days, else a new one.
    automatic = Message.create!(sender: contact, receiver: admin, message: 'No thread given')
    assert_equal thread.id, automatic.reload.thread_table_id
    stranger = Message.create!(sender: chat_contact(visitor_token: nil, email: 'z@example.com'), receiver: admin, message: 'New pair')
    assert stranger.reload.thread_table_id.present?
    refute_equal thread.id, stranger.thread_table_id

    # One party only (a chat message to the store, a note): no automatic thread, no error.
    lone = Message.create!(sender: contact, message: 'To the store')
    assert_nil lone.reload.thread_table_id
  end

  test 'messages hold attachments' do
    message = ThreadTable.create!(contact: chat_contact).messages.create!(direction: 'inbound', message: 'Photo')
    message.attachments.attach(media_blob(ShopMediaTestHelper::PNG_BYTES, 'photo.png', 'image/png'))

    assert_equal ['photo.png'], message.reload.attachments.map { |a| a.filename.to_s }
  end

  test 'a visitor session is online for 2 minutes and live for 30, and its cart is an incomplete order' do
    contact = chat_contact
    now = Time.current
    session = contact.visitor_sessions.create!(token: 'tok-1', started_at: now - 10.minutes, last_seen_at: now - 1.minute)
    stale = contact.visitor_sessions.create!(token: 'tok-2', started_at: now - 2.hours, last_seen_at: now - 40.minutes)

    assert session.online?(now)
    refute session.reload.online?(now + 2.minutes)
    assert session.live?(now + 20.minutes)
    refute stale.live?(now)
    assert_equal [session], VisitorSession.online(now).to_a
    assert_equal [stale], VisitorSession.offline(now).to_a

    cart = chat_cart
    session.update!(order: cart)
    assert_equal cart, session.cart
    cart.update_columns(state: 'complete', completed_at: now)
    assert_nil session.reload.cart
  end

  test 'deleting a contact deletes its sessions and page views and keeps its conversations' do
    contact = chat_contact
    session = contact.visitor_sessions.create!(token: 'tok-3', started_at: Time.current, last_seen_at: Time.current)
    VisitorPageView.create!(visitor_session: session, url: '/a', created_at: Time.current)
    conversation = ThreadTable.create!(contact: contact)

    contact.destroy!

    refute VisitorSession.exists?(session.id)
    assert_equal 0, VisitorPageView.where(visitor_session_id: session.id).count
    assert_nil conversation.reload.contact_id
  end
end
