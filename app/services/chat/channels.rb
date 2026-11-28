module Chat
  # The channels a conversation's replies go out on. A channel is a class with:
  #
  #   deliver(message)       sends a staff reply (direction 'outbound'); sets its delivery_status
  #                          ('sent', 'delivered' or 'failed') and, when the provider gives one,
  #                          its external_id. It must not raise for a provider error.
  #   receive(payload)       optional: turns a provider's inbound payload (a webhook, a parsed
  #                          email) into Chat::Conversations.post_inbound calls. None of the
  #                          channels here receive yet; inbound email, SMS, WhatsApp and Instagram
  #                          plug in later through this interface.
  #
  #   Chat::Channels.register('sms', MyApp::SmsChannel)
  #
  # Built in: web (the storefront widget, which polls) and email (the "You have a reply" email).
  module Channels
    module_function

    def registry
      @registry ||= {}
    end

    def register(name, klass)
      registry[name.to_s] = klass
    end

    def unregister(name)
      registry.delete(name.to_s)
    end

    def [](name)
      registry[name.to_s]
    end

    def names
      registry.keys
    end

    # Delivers a staff reply on its conversation's channel (web when none or unknown). Errors are
    # logged and mark the message failed; they never undo the reply.
    def deliver(message)
      name = message.thread_table&.channel.presence || 'web'
      klass = self[name] || self['web']
      return unless klass

      klass.new.deliver(message)
    rescue StandardError => e
      Rails.logger.error("[chat] delivering message #{message.id} on #{name} failed: #{e.class}")
      message.update_column(:delivery_status, 'failed') if message.persisted?
    end
  end
end
