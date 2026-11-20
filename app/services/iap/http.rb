require 'net/http'
require 'json'

module Iap
  # Minimal JSON-over-HTTPS client for the store APIs. Maps failures to
  # Iap::Error codes and never logs headers, bodies or full URLs (they can hold
  # tokens).
  module Http
    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, IOError, Timeout::Error,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError
    ].freeze

    module_function

    def request(method, url, headers: {}, json: nil, form: nil, config: Iap.config)
      uri = URI(url)
      req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      headers.each { |k, v| req[k] = v }
      req['Accept'] = 'application/json'
      if form
        req.set_form_data(form)
      elsif json
        req['Content-Type'] = 'application/json'
        req.body = json.to_json
      elsif method == :post
        req.body = ''
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                open_timeout: config.open_timeout, read_timeout: config.read_timeout) do |http|
        http.request(req)
      end
      handle(res, uri)
    rescue *NETWORK_ERRORS => e
      Rails.logger.warn("[iap] #{uri&.host} unreachable: #{e.class}")
      raise Iap::Error.new(:store_unreachable)
    end

    def handle(res, uri)
      code = res.code.to_i
      case code
      when 200..299
        res.body.to_s.strip.empty? ? {} : JSON.parse(res.body)
      when 400, 404, 410
        raise Iap::Error.new(:invalid_purchase, "store rejected the purchase (HTTP #{code})")
      else
        Rails.logger.warn("[iap] #{uri.host} answered HTTP #{code}")
        raise Iap::Error.new(:store_unreachable, "store unavailable (HTTP #{code})")
      end
    rescue JSON::ParserError
      raise Iap::Error.new(:store_unreachable, 'store sent an unreadable response')
    end
  end
end
