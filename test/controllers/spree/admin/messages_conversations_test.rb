require 'test_helper'

# Admin messages: the list, and the Conversations inbox it links to.
# Both used to 500 (a link to a route that does not exist, and an action
# that had been deleted).
class Spree::Admin::MessagesConversationsTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = create(:user, email: 'support@example.com')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    login_as(@admin, scope: :spree_user)

    @contact = Contact.create!(full_name: 'Robin Customer', email: 'robin@example.com')
    thread = ThreadTable.create!(archived: false)
    Message.create!(sender: @contact, receiver: @admin, thread_table: thread, message: 'Has my order shipped?', created_at: 2.minutes.ago)
    Message.create!(sender: @admin, receiver: @contact, thread_table: thread, message: 'Yes, it left today.', created_at: 1.minute.ago)
  end

  teardown { Warden.test_reset! }

  def users_param
    [{ type: 'Contact', id: @contact.id }, { type: 'User', id: @admin.id }]
  end

  test 'the messages list gives way to the inbox, and its conversation pages still open' do
    get '/admin/messages'
    assert_redirected_to '/admin/inbox'

    get "/admin/messages/conversation?id=#{Message.first.id}"
    assert_response :success
  end

  test 'the inbox lists each pair once, whichever way the messages went' do
    get '/admin/messages/conversations'

    assert_response :success
    assert_select '.conversation-item', 1
    assert_select '.conversation-item .participant-name', text: 'Robin Customer'
  end

  test 'an open conversation shows both sides, in order' do
    get '/admin/messages/conversations', params: { users: users_param }

    assert_response :success
    bubbles = css_select('.chat-bubble').map(&:text)
    assert_equal 2, bubbles.size
    assert_match 'Has my order shipped?', bubbles.first
    assert_match 'Yes, it left today.', bubbles.last
    assert_select 'a', text: '← All conversations'
  end

  test 'no customer names are sent to a third-party avatar service' do
    get '/admin/messages/conversations', params: { users: users_param }

    assert_no_match(/ui-avatars\.com/, response.body)
    assert_select '.initials-avatar', text: 'RC'
  end
end
