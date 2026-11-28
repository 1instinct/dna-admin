require 'test_helper'

# The older Rails admin pages for contacts, threads and messages still render with chat data:
# visitor contacts without an account, conversations, one-party messages and staff notes.
class Spree::Admin::ChatAdminPagesTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ChatTestHelper

  setup do
    @admin = chat_admin(email: 'support@example.com')
    login_as(@admin, scope: :spree_user)
    @contact = chat_contact(name: 'Robin Visitor', email: 'robin@example.com')
    @conversation = chat_conversation(@contact, body: 'Do you ship abroad?')
    Chat::Conversations.post_outbound(@conversation, @admin, body: 'Yes, worldwide.')
    Chat::Conversations.note(@conversation, @admin, body: 'Asked twice before')
    # An older two-party conversation alongside.
    @legacy_contact = Contact.create!(full_name: 'Legacy Customer', email: 'legacy@example.com')
    thread = ThreadTable.create!(archived: false)
    Message.create!(sender: @legacy_contact, receiver: @admin, thread_table: thread, message: 'Old question')
  end

  teardown { Warden.test_reset! }

  test 'contacts list and pages' do
    get '/admin/contacts'
    assert_response :success
    assert_includes response.body, 'Robin Visitor'

    get "/admin/contacts/#{@contact.id}"
    assert_response :success
    get "/admin/contacts/#{@contact.id}/edit"
    assert_response :success
  end

  test 'threads list, page and conversation' do
    get '/admin/threads'
    assert_response :success

    get "/admin/threads/#{@conversation.id}"
    assert_response :success
    get "/admin/threads/#{@conversation.id}/conversation"
    assert_response :success
    assert_includes response.body, 'Do you ship abroad?'
    assert_includes response.body, 'Yes, worldwide.'
  end

  test 'messages list and the two-pane inbox' do
    get '/admin/messages'
    assert_response :success
    assert_includes response.body, 'Do you ship abroad?'

    get '/admin/messages/conversations'
    assert_response :success
    assert_select '.participant-name', text: 'Legacy Customer'

    get "/admin/messages/conversation?id=#{@conversation.messages.outbound.first.id}"
    assert_response :success
    get "/admin/messages/conversation?id=#{@conversation.messages.inbound.first.id}"
    assert_redirected_to "/admin/threads/#{@conversation.id}/conversation"
  end
end
