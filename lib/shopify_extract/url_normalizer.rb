require "uri"

module ShopifyExtract
  # Strips Shopify CDN version/size query parameters from image URLs
  # so identical content is detected across runs regardless of URL version hashes.
  module UrlNormalizer
    STRIPPED_PARAMS = %w[v width height crop format quality].freeze

    def self.call(url)
      return nil if url.nil?
      raise URI::InvalidURIError, "not a URL: #{url.inspect}" unless url.match?(%r{\Ahttps?://})

      uri = URI.parse(url)
      if uri.query
        params = URI.decode_www_form(uri.query).reject { |k, _| STRIPPED_PARAMS.include?(k) }
        uri.query = params.any? ? URI.encode_www_form(params) : nil
      end
      uri.to_s
    end
  end
end
