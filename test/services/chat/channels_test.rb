require 'test_helper'
require 'minitest/mock'

# Chat::Channels: the registry, the web channel and the "You have a reply" email with its signed
# link back to the conversation.
class Chat::ChannelsTest < ActiveSupport::TestCase
  include ChatTestHelper
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  setup do
    Chat.config.storefront_url = 'https://shop.example.com/'
    @admin = chat_admin
    @contact = chat_contact(email: 'ada@example.com')
    @conversation = chat_conversation(@contact)
  end

  teardown do
    Chat.reset_config!
    Chat::Channels.unregister('test')
  end

  def away!(contact = @contact, since: 10.minutes.ago)
    contact.update_columns(last_seen_at: since)
  end

  test 'web and email are registered, and more channels plug in' do
    assert_equal Chat::Channels::Web, Chat::Channels['web']
    assert_equal Chat::Channels::Email, Chat::Channels['email']

    sent = []
    Chat::Channels.register('test', Class.new { define_method(:deliver) { |m| sent << m } })
    @conversation.update!(channel: 'test')
    away!
    message = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Via test')

    assert_equal [message], sent
    assert_includes Chat::Channels.names, 'test'
  end

  test 'an unknown channel falls back to web' do
    @conversation.update!(channel: 'carrier-pigeon')

    message = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Hi')

    assert_equal 'sent', message.reload.delivery_status
  end

  test 'a channel error marks the reply failed and keeps it' do
    Chat::Channels.register('test', Class.new { define_method(:deliver) { |_m| raise 'provider down' } })
    @conversation.update!(channel: 'test')

    message = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Hi')

    assert message.persisted?
    assert_equal 'failed', message.reload.delivery_status
  end

  test 'the web channel sends nothing while the customer is on the storefront' do
    @contact.update_columns(last_seen_at: 1.minute.ago)

    assert_no_enqueued_emails do
      message = Chat::Conversations.post_outbound(@conversation, @admin, body: 'Right here')
      assert_equal %w[web sent], [message.reload.channel, message.delivery_status]
    end
  end

  test 'a reply is emailed when the customer has left and gave an email' do
    away!

    message = nil
    assert_enqueued_emails(1) { message = Chat::Conversations.post_outbound(@conversation, @admin, body: 'We have it in blue') }
    assert_equal %w[email sent], [message.reload.channel, message.delivery_status]

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal ['ada@example.com'], mail.to
    assert_match 'You have a reply', mail.subject
    assert_equal %w[text/html text/plain], mail.parts.map(&:mime_type).sort
    text = mail.text_part.body.to_s
    html = mail.html_part.body.to_s
    assert_includes text, 'We have it in blue'
    assert_includes html, 'We have it in blue'
    link = text[%r{https://shop\.example\.com/\?chat=\S+}]
    assert link, 'the email links back to the storefront chat'
    assert_includes html, ERB::Util.html_escape(link)
    token = CGI.unescape(link.split('chat=', 2).last)
    assert_equal @conversation, Chat.conversation_for_resume_token(token)
  end

  test 'no email without an address, without a storefront URL, or for a note' do
    away!
    @contact.update_columns(email: nil)
    assert_no_enqueued_emails { Chat::Conversations.post_outbound(@conversation, @admin, body: 'No address') }

    @contact.update_columns(email: 'ada@example.com')
    Chat.config.storefront_url = ''
    assert_no_enqueued_emails { Chat::Conversations.post_outbound(@conversation, @admin, body: 'No storefront') }

    Chat.config.storefront_url = 'https://shop.example.com'
    assert_no_enqueued_emails { Chat::Conversations.note(@conversation, @admin, body: 'Internal') }
  end

  test 'one email per absence: more replies within the throttle are not emailed again' do
    away!(since: 1.hour.ago)
    assert_enqueued_emails(1) do
      Chat::Conversations.post_outbound(@conversation, @admin, body: 'First')
      Chat::Conversations.post_outbound(@conversation, @admin, body: 'Second')
    end

    travel 16.minutes do
      assert_enqueued_emails(1) { Chat::Conversations.post_outbound(@conversation, @admin, body: 'Much later') }
    end
  end

  test 'a customer who came back and left again gets the next reply by email' do
    away!(since: 1.hour.ago)
    assert_enqueued_emails(1) { Chat::Conversations.post_outbound(@conversation, @admin, body: 'First') }

    travel 6.minutes do
      @contact.update_columns(last_seen_at: 5.minutes.ago - 1.second)
      assert_enqueued_emails(1) { Chat::Conversations.post_outbound(@conversation, @admin, body: 'After their visit') }
    end
  end

  test 'resume tokens name the conversation and its contact, and expire' do
    token = Chat.resume_token(@conversation)

    assert_equal @conversation, Chat.conversation_for_resume_token(token)
    assert_nil Chat.conversation_for_resume_token("#{token}x")
    assert_nil Chat.conversation_for_resume_token('')
    assert_nil Chat.conversation_for_resume_token(nil)
    other = Rails.application.message_verifier(:something_else).generate({ 'conversation_id' => @conversation.id,
                                                                          'contact_id' => @contact.id })
    assert_nil Chat.conversation_for_resume_token(other)

    @conversation.update!(contact: chat_contact(email: 'someone@example.com'))
    assert_nil Chat.conversation_for_resume_token(token), 'a conversation moved to another contact'

    @conversation.update!(contact: @contact)
    travel 31.days do
      assert_nil Chat.conversation_for_resume_token(token)
    end
  end

  test 'the store shows as online with a recently used admin device or in business hours' do
    refute Chat.staff_online?

    Chat.config.business_hours = { days: [1, 2, 3, 4, 5], from: '09:00', to: '17:00' }
    Chat.config.time_zone = 'UTC'
    assert Chat.staff_online?(Time.utc(2026, 11, 30, 10, 0))   # Monday
    refute Chat.staff_online?(Time.utc(2026, 11, 29, 10, 0))   # Sunday
    refute Chat.staff_online?(Time.utc(2026, 11, 30, 17, 0))

    Chat.config.business_hours = nil
    SpreeAdminNative::Device.create!(owner: @admin, name: 'Phone', token_digest: SecureRandom.hex(16),
                                     last_used_at: 3.minutes.ago)
    assert Chat.staff_online?
    travel 11.minutes do
      refute Chat.staff_online?
    end
  end

  test 'business hours parse from the environment format' do
    assert_equal({ days: [1, 2, 3, 4, 5], from: '09:00', to: '17:00' }, Chat::BusinessHours.parse('1-5 09:00-17:00'))
    assert_equal({ days: [6, 7, 1], from: '22:00', to: '02:00' }, Chat::BusinessHours.parse('6-1 22:00-02:00'))
    assert_nil Chat::BusinessHours.parse('weekdays')
    assert Chat::BusinessHours.open?({ days: [6], from: '22:00', to: '02:00' }, Time.utc(2026, 11, 28, 23, 0))
  end
end
