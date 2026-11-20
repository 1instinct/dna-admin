require 'net/http'

module UserTracks
  # Fetches the generator's audio to a local file: HTTPS only (redirects too, at most 3), at most
  # UserTracks.config.max_download_bytes, and no credentials sent. The URL is never logged or put
  # in an error message (it can be a signed URL).
  #
  #   UserTracks::Download.call(url, to: path)
  #
  # Raises Download::Error with code :unreachable (network, 5xx: worth trying again) or :refused
  # (not HTTPS, 4xx, too large, too many redirects).
  module Download
    class Error < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    MAX_REDIRECTS = 3

    module_function

    def call(url, to:, config: UserTracks.config)
      uri = https_uri(url)
      (MAX_REDIRECTS + 1).times do
        location = fetch(uri, to, config)
        return to unless location

        uri = https_uri(URI.join(uri.to_s, location).to_s)
      end
      raise Error.new(:refused, 'too many redirects')
    rescue *UserTracks::Fal::NETWORK_ERRORS => e
      raise Error.new(:unreachable, "download failed (#{e.class})")
    end

    # Writes the body to `to` and answers nil, or answers a redirect's Location.
    def fetch(uri, to, config)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: config.open_timeout,
                                          read_timeout: config.read_timeout * 4) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |res|
          code = res.code.to_i
          return res['location'].presence || raise(Error.new(:refused, 'redirect without a location')) if (300..399).cover?(code)
          raise Error.new(code >= 500 ? :unreachable : :refused, "download answered HTTP #{code}") unless code == 200

          write(res, to, config.max_download_bytes)
        end
      end
      nil
    end

    def write(res, to, limit)
      size = 0
      File.open(to, 'wb') do |file|
        res.read_body do |chunk|
          size += chunk.bytesize
          raise Error.new(:refused, 'download too large') if size > limit

          file.write(chunk)
        end
      end
      raise Error.new(:refused, 'download was empty') if size.zero?
    end

    def https_uri(url)
      uri = URI.parse(url.to_s)
      raise Error.new(:refused, 'not an https URL') unless uri.scheme == 'https' && uri.host.present? && uri.userinfo.nil?

      uri
    rescue URI::InvalidURIError
      raise Error.new(:refused, 'not a URL')
    end
  end
end
