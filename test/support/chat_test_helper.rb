# Shared helpers for the chat, visitor and inbox tests.
require 'minitest/mock'
require_relative 'shop_media_test_helper'

module ChatTestHelper
  include ShopMediaTestHelper

  def chat_admin(email: "staff-#{SecureRandom.hex(3)}@example.com")
    user = Spree.user_class.create!(email: email, password: 'password123')
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  def chat_contact(**attrs)
    Contact.create!({ visitor_token: Contact.generate_visitor_token, name: 'Ada Example', email: 'ada@example.com' }.merge(attrs))
  end

  # A conversation with one inbound message.
  def chat_conversation(contact = chat_contact, body: 'Is this in stock?')
    conversation, = Chat::Conversations.find_or_create(contact)
    Chat::Conversations.post_inbound(conversation, body: body)
    conversation.reload
  end

  # An order in the cart state holding one product (with an image), quantity 2 at 12.50.
  def chat_cart(user: nil, email: 'ada@example.com', state: 'cart', image: true)
    product = media_product(name: "Mug #{SecureRandom.hex(2)}", price: 12.5)
    media_image(product.master, ShopMediaTestHelper::PNG_BYTES, 'mug.png', 'image/png', width: 1, height: 1) if image
    order = Spree::Order.create!(user: user, email: email, store: media_store, currency: 'USD')
    # Stock and store availability are not what these tests are about.
    order.line_items.new(variant: product.master, quantity: 2, price: 12.5, currency: 'USD').save!(validate: false)
    order.update_columns(state: state, item_count: 2, total: 25)
    order.reload
  end

  def completed_order(user: nil, email: 'ada@example.com', completed_at: 1.day.ago)
    order = Spree::Order.create!(user: user, email: email, store: media_store, currency: 'USD')
    order.update_columns(state: 'complete', completed_at: completed_at, total: 40)
    order
  end

  # Fresh, isolated rate-limit counters for the block's tests.
  def with_rate_limit_store
    Chat.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Chat.config.rate_limit_store = nil
  end

  # Records the admin app pushes (SpreeAdminNative::Inbox.notify_inbound) made in the block.
  def capturing_inbox_pushes(&block)
    calls = []
    SpreeAdminNative::Inbox.stub(:notify_inbound, ->(conversation, message) { calls << [conversation, message] }) do
      block.call(calls)
    end
  end
end
