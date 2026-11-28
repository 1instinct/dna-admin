# Customer chat and visitor tracking (app/services/chat.rb and visitors.rb hold the settings and
# list their ENV names).
#
# 1. Channels: web (the storefront widget) and email ("You have a reply"). A fork or extension
#    registers more in its own initializer: Chat::Channels.register('sms', MyApp::SmsChannel).
# 1. The chat's rate limits live in Rails.cache: a shared store (Memcached, Redis) makes them hold
#    across processes.
# 1. Every request records its base URL (Chat::Current), so attachment and product image URLs in
#    the adapters' payloads are absolute.
# 1. Rake: `rake chat:backfill` once after the chat migrations, `rake visitors:prune` daily.
Rails.application.config.to_prepare do
  Chat::Channels.register('web', Chat::Channels::Web)
  Chat::Channels.register('email', Chat::Channels::Email)
end

ActiveSupport.on_load(:action_controller) do
  prepend_before_action { Chat::Current.base_url = request.base_url }
end
