require 'net/http'
require 'json'

# Looks up the version of an app that is live on the US App Store (public iTunes lookup API).
# Used by AppSetting to refuse an iOS minimum the store can't satisfy yet.
class AppStoreLookup
  class Error < StandardError; end

  LOOKUP_URL = 'https://itunes.apple.com/lookup'.freeze
  TIMEOUT = 3 # seconds, for both open and read

  # Returns the live version string, or nil when the store has no such app.
  # Raises AppStoreLookup::Error when the lookup itself fails.
  def self.live_version(bundle_id)
    data = JSON.parse(fetch(bundle_id))
    result = data.is_a?(Hash) && data['results'].is_a?(Array) ? data['results'].first : nil
    result.is_a?(Hash) ? result['version'].presence : nil
  rescue JSON::ParserError => e
    raise Error, "unreadable response (#{e.class})"
  end

  def self.fetch(bundle_id)
    uri = URI(LOOKUP_URL)
    uri.query = URI.encode_www_form(bundleId: bundle_id, country: 'us')
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
    raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body.to_s
  rescue Error
    raise
  rescue StandardError => e
    raise Error, e.class.name
  end
end
