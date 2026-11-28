module Chat
  # Absolute URLs for attachments and product images in chat and visitor payloads. The host is the
  # current request's (Chat::Current.base_url, set for every controller in
  # config/initializers/chat.rb), else Rails.application.routes.default_url_options, else the
  # URL is a path.
  module Urls
    module_function

    def blob(attachable)
      url_for(attachable) { |helpers, options| helpers.rails_blob_url(attachable, **options) }
    end

    # A Spree::Image rendition (Spree::Image#url(style)), as the storefront API links them.
    def image(image, style = :small)
      return unless image&.attachment&.attached?

      url_for(image) { |helpers, options| helpers.polymorphic_url(image.url(style), **options) }
    rescue StandardError
      nil
    end

    def url_for(_record)
      helpers = Rails.application.routes.url_helpers
      options = host_options
      return yield(helpers, options) if options[:host]

      yield(helpers, only_path: true)
    rescue StandardError
      nil
    end

    def host_options
      base = Chat::Current.base_url.presence
      if base
        uri = URI.parse(base)
        return { host: uri.host, port: uri.port, protocol: uri.scheme }.compact.tap do |o|
          o.delete(:port) if [80, 443].include?(o[:port])
        end
      end

      (Rails.application.routes.default_url_options || {}).symbolize_keys.slice(:host, :port, :protocol)
    rescue URI::InvalidURIError
      {}
    end
  end
end
