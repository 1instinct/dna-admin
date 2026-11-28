# Customer chat: conversations (ThreadTable with a contact), their messages, the channels replies
# go out on, and the storefront's chat API (Spree::Api::V1::Storefront::ChatController).
#
# Settings live on Chat.config; ENV is read unless a value was set (tests set them directly).
#
# ENV:
#   CHAT_GREETING         the widget's greeting (default "Hi! How can we help?")
#   CHAT_STOREFRONT_URL   storefront base for the "You have a reply" email link (falls back to
#                         SITE_URL); no reply email is sent without one
#   CHAT_BUSINESS_HOURS   when the widget shows the store as online without a staff device active,
#                         e.g. "1-5 09:00-17:00" (ISO weekdays, Monday is 1); unset means never
#   CHAT_TIME_ZONE        time zone for CHAT_BUSINESS_HOURS (default the app's, UTC)
module Chat
  class Config
    attr_writer :greeting, :storefront_url, :business_hours, :time_zone
    attr_accessor :rate_limits, :rate_limit_store, :offline_after, :email_throttle, :staff_active_within,
                  :resume_token_ttl, :staff_display_name

    def initialize
      # Fixed windows (Chat::RateLimit). message: per visitor token; new_conversation: per IP;
      # request: every storefront chat or visit request, per token and per IP; resume: per IP.
      @rate_limits = {
        message: { limit: 20, window: 1.minute },
        new_conversation: { limit: 5, window: 1.hour },
        request: { limit: 120, window: 1.minute },
        ip_request: { limit: 600, window: 1.minute },
        resume: { limit: 20, window: 10.minutes }
      }
      # nil uses Rails.cache (or a process-local store when Rails.cache is a NullStore).
      @rate_limit_store = nil
      # The reply email goes out when the customer hasn't been seen for this long.
      @offline_after = 5.minutes
      # At most one reply email per conversation in this window while the customer stays away.
      @email_throttle = 15.minutes
      # The widget shows staff online when a paired admin device was used this recently.
      @staff_active_within = 10.minutes
      @resume_token_ttl = 30.days
      # The name customers see on staff replies; nil uses the default store's name.
      @staff_display_name = nil
    end

    def greeting
      defined?(@greeting) ? @greeting : (ENV['CHAT_GREETING'].presence || 'Hi! How can we help?')
    end

    # Without a trailing slash; nil when unset or not http(s).
    def storefront_url
      value = defined?(@storefront_url) ? @storefront_url : (ENV['CHAT_STOREFRONT_URL'].presence || ENV['SITE_URL'])
      value = value.to_s.strip.chomp('/')
      value if value.match?(%r{\Ahttps?://}i)
    end

    # { days: [1..7 ISO weekdays], from: "HH:MM", to: "HH:MM" } or nil.
    def business_hours
      return @business_hours if defined?(@business_hours)

      Chat::BusinessHours.parse(ENV['CHAT_BUSINESS_HOURS'])
    end

    def time_zone
      defined?(@time_zone) ? @time_zone : (ENV['CHAT_TIME_ZONE'].presence || Time.zone&.name || 'UTC')
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Tests use this to drop changed settings.
  def self.reset_config!
    @config = nil
  end

  # Signed links back to a conversation (the reply email's ?chat=<token>).
  def self.resume_verifier
    Rails.application.message_verifier(:chat_resume)
  end

  def self.resume_token(conversation)
    resume_verifier.generate({ 'conversation_id' => conversation.id, 'contact_id' => conversation.contact_id },
                             purpose: :chat_resume, expires_in: config.resume_token_ttl)
  end

  # The conversation a resume token names, or nil when it is invalid, expired, or no longer
  # belongs to that contact.
  def self.conversation_for_resume_token(token)
    return if token.blank?

    data = resume_verifier.verified(token.to_s, purpose: :chat_resume)
    return unless data.is_a?(Hash)

    ThreadTable.conversations.find_by(id: data['conversation_id'], contact_id: data['contact_id'])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Staff are reachable: a paired admin device was used recently, or it is business hours.
  def self.staff_online?(now = Time.current)
    staff_device_active?(now) || Chat::BusinessHours.open?(config.business_hours, now.in_time_zone(config.time_zone))
  end

  def self.staff_device_active?(now = Time.current)
    return false unless SpreeAdminNative::Device.table_exists?

    SpreeAdminNative::Device.active.where('last_used_at >= ?', now - config.staff_active_within).exists?
  rescue ActiveRecord::ActiveRecordError
    false
  end

  def self.staff_display_name
    config.staff_display_name.presence || Spree::Store.default&.name.presence || 'Support'
  end
end
