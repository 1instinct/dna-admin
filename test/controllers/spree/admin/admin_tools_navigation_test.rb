require 'test_helper'

# The sidebar's Menus, Inbox and Visitors entries replace Contacts, Messages, Threads and the menu
# navigator, and those older index pages redirect; their other pages and JSON stay for forks.
class Spree::Admin::AdminToolsNavigationTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ChatTestHelper

  setup do
    @admin = chat_admin(email: 'nav-admin@example.com')
    login_as(@admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'the sidebar shows Menus, Inbox with the unread count and Visitors, and not the older entries' do
    chat_conversation(chat_contact)
    chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'b@example.com'))
    read = chat_conversation(chat_contact(visitor_token: Contact.generate_visitor_token, email: 'c@example.com'))
    Chat::Conversations.mark_read_by_staff(read)

    get '/admin/menus'
    assert_response :success
    assert_select '#main-sidebar' do
      assert_select '#sidebarMenus li.selected a[href="/admin/menus"]', text: /Menus/
      assert_select '#sidebarInbox a[href="/admin/inbox"]', text: /Inbox/
      assert_select '#sidebarInbox [data-inbox-unread-badge]:not(.d-none) [data-count]', text: '2'
      assert_select '#sidebarVisitors a[href="/admin/visitors"]', text: /Visitors/
      assert_select 'a[href="/admin/contacts"]', 0
      assert_select 'a[href="/admin/threads"]', 0
      assert_select 'a[href="/admin/messages"]', 0
      assert_select 'a[href="/admin/menu_items"]', 0
      assert_select '#sidebar-messages', 0
    end
    # Menus sits where the menu navigator was, and Inbox and Visitors where Contacts was.
    order = css_select('#main-sidebar > nav > ul').map { |ul| ul['id'] }
    assert_equal %w[sidebarMenus sidebarLiveStream sidebarInbox sidebarVisitors], order & %w[sidebarMenus sidebarLiveStream sidebarInbox sidebarVisitors]

    get '/admin/inbox'
    assert_select '#sidebarInbox li.selected'
  end

  test 'with nothing unread the badge is hidden' do
    get '/admin/visitors'
    assert_select '#sidebarInbox [data-inbox-unread-badge].d-none'
    assert_select '#sidebarVisitors li.selected'
  end

  test 'the older index pages redirect' do
    {
      '/admin/contacts' => '/admin/inbox',
      '/admin/threads' => '/admin/inbox',
      '/admin/messages' => '/admin/inbox',
      '/admin/menu_items' => '/admin/menus',
      '/admin/menu_locations' => '/admin/menus'
    }.each do |from, to|
      get from
      assert_redirected_to to, "#{from} redirects to #{to}"
    end
  end

  test 'their record pages and the menu items JSON stay' do
    contact = chat_contact
    conversation = chat_conversation(contact)
    location = MenuLocation.create!(title: 'Main', location: 'header', is_visible: true)
    item = MenuItem.create!(name: 'Shop', menu_location: location, url: '/shop')

    get "/admin/contacts/#{contact.id}"
    assert_response :success
    get "/admin/threads/#{conversation.id}/conversation"
    assert_response :success
    get "/admin/menu_items/#{item.id}/edit"
    assert_response :success
    get "/admin/menu_locations/#{location.id}"
    assert_response :success
    get '/admin/menu_items.json'
    assert_response :success
  end

  test 'non-admins see none of it' do
    user = Spree.user_class.create!(email: 'shopper@example.com', password: 'password123')
    login_as(user, scope: :spree_user)
    %w[/admin/menus /admin/inbox /admin/visitors /admin/contacts /admin/menu_items].each do |path|
      get path
      assert_redirected_to '/forbidden', path
    end
  end
end
