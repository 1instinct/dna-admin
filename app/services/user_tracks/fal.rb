require 'net/http'
require 'json'
require 'cgi'

module UserTracks
  # fal.ai queue client for the track generator (UserTracks.config.fal_model).
  #
  #   submit(input, webhook_url:) -> request_id   POST <queue>/<model>?fal_webhook=<url>
  #   status(request_id) -> :in_queue | :in_progress | :completed | :failed
  #   result(request_id) -> { audio_url:, content_type: }
  #
  # Status and result URLs use the owner and app only (fal-ai/ace-step-1.5 has no sub-path).
  # fal reports a failed request as COMPLETED with an `error`; that is :failed here, as is a request
  # fal doesn't know (404). Errors raise Fal::Error with a code: :not_configured, :unauthorized,
  # :rejected (fal refused the input), :failed (generation failed or the answer is unusable),
  # :unreachable (network, timeout, 429 or 5xx: worth asking again later).
  #
  # The key goes only to the queue host, never to the audio URL's host; neither the key, the
  # webhook URL nor the audio URL is logged or put in an error message.
  class Fal
    class Error < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code
        super(message || code.to_s)
      end
    end

    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, IOError, Timeout::Error,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError
    ].freeze
    STATUSES = { 'IN_QUEUE' => :in_queue, 'IN_PROGRESS' => :in_progress, 'COMPLETED' => :completed }.freeze
    REQUEST_ID = /\A[A-Za-z0-9_-]{1,128}\z/.freeze

    attr_reader :config

    def initialize(config: UserTracks.config)
      @config = config
    end

    def configured?
      config.fal_key.present?
    end

    def submit(input, webhook_url:)
      url = model_url
      url += "?fal_webhook=#{CGI.escape(webhook_url)}" if webhook_url.present?
      body = call(:post, url, json: input)
      request_id = body['request_id'].to_s
      raise Error.new(:unreachable, 'fal answered without a request id') unless request_id.match?(REQUEST_ID)

      request_id
    end

    def status(request_id)
      body = call(:get, "#{requests_url(request_id)}/status")
      return :failed if body['error'].present?

      STATUSES.fetch(body['status'].to_s, :in_progress)
    rescue Error => e
      return :failed if e.code == :not_found

      raise
    end

    def result(request_id)
      body = call(:get, requests_url(request_id))
      raise Error.new(:failed, 'generation failed') if body['error'].present?

      audio = body['audio'].is_a?(Hash) ? body['audio'] : {}
      url = audio['url'].to_s
      raise Error.new(:failed, 'no audio in the result') unless https?(url)

      { audio_url: url, content_type: audio['content_type'].presence || 'audio/flac' }
    rescue Error => e
      raise Error.new(:failed, 'generation failed') if %i[not_found rejected].include?(e.code)

      raise
    end

    private

    def model_url
      "#{config.fal_queue_base.chomp('/')}/#{config.fal_model}"
    end

    def requests_url(request_id)
      raise Error.new(:failed, 'bad request id') unless request_id.to_s.match?(REQUEST_ID)

      "#{model_url}/requests/#{request_id}"
    end

    def https?(url)
      uri = URI.parse(url)
      uri.scheme == 'https' && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def call(method, url, json: nil)
      raise Error.new(:not_configured, 'FAL_KEY is not set') unless configured?

      uri = URI(url)
      req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      req['Authorization'] = "Key #{config.fal_key}"
      req['Accept'] = 'application/json'
      if method == :post
        req['Content-Type'] = 'application/json'
        req.body = (json || {}).to_json
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                open_timeout: config.open_timeout, read_timeout: config.read_timeout) do |http|
        http.request(req)
      end
      handle(res)
    rescue *NETWORK_ERRORS => e
      log("unreachable (#{e.class})")
      raise Error.new(:unreachable, 'fal unreachable')
    end

    def handle(res)
      code = res.code.to_i
      error =
        case code
        when 200..299 then nil
        when 401, 403 then :unauthorized
        when 404 then :not_found
        when 400, 405, 409, 410, 422 then :rejected
        else :unreachable
        end
      unless error
        parsed = res.body.to_s.strip.empty? ? {} : JSON.parse(res.body)
        return parsed.is_a?(Hash) ? parsed : {}
      end

      log("answered HTTP #{code}")
      raise Error.new(error, "fal answered HTTP #{code}")
    rescue JSON::ParserError
      log('sent an unreadable answer')
      raise Error.new(:unreachable, 'fal sent an unreadable answer')
    end

    def log(what)
      Rails.logger.warn("[user_tracks] fal #{what}")
    end
  end
end
