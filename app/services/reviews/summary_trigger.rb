require 'net/http'

module Reviews
  # Asks the storefront to refresh stale AI review summaries (M7, "Trigger" in
  # docs/plans/2026-11-26-reviews-api-contract.md):
  #
  #   POST #{SITE_URL}/api/internal/reviews/summarize
  #   Authorization: Bearer #{INTERNAL_CRON_SECRET}
  #
  # The storefront then pulls the stale list from GET /api/v1/admin/review_summaries/stale and PUTs
  # each summary back. Called once per `rake reviews:dispatch` run, and by Regenerate on a product's
  # Reviews tab (in a thread, so the admin page doesn't wait for the model). Never raises: every
  # failure is logged and comes back as a status.
  #
  #   Reviews::SummaryTrigger.call # => :ok | :not_configured | :failed (non-2xx) | :error (exception)
  module SummaryTrigger
    PATH = '/api/internal/reviews/summarize'.freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 300

    module_function

    def site_url(env = ENV)
      env['SITE_URL'].to_s.strip.chomp('/')
    end

    def secret(env = ENV)
      env['INTERNAL_CRON_SECRET'].to_s.strip
    end

    # Both SITE_URL and INTERNAL_CRON_SECRET are set.
    def configured?(env = ENV)
      site_url(env).present? && secret(env).present?
    end

    def call(env: ENV, logger: Rails.logger)
      return :not_configured unless configured?(env)

      uri = URI.parse("#{site_url(env)}#{PATH}")
      raise ArgumentError, "SITE_URL #{site_url(env).inspect} isn't an absolute http(s) URL" unless uri.is_a?(URI::HTTP) && uri.host

      response = post(uri, secret(env))
      if response.is_a?(Net::HTTPSuccess)
        logger.info("[reviews] AI summary refresh: #{response.code} #{response.body.to_s.truncate(200)}")
        :ok
      else
        logger.warn("[reviews] AI summary refresh failed: HTTP #{response.code} #{response.body.to_s.truncate(200)}")
        :failed
      end
    rescue StandardError => e
      logger.error("[reviews] AI summary refresh error: #{e.class}: #{e.message}")
      :error
    end

    # The same call on a background thread; returns the Thread. For the admin's Regenerate button:
    # the storefront answers only when the whole batch is written, which can take minutes.
    def call_in_background(env: ENV.to_h, logger: Rails.logger)
      Thread.new { call(env: env, logger: logger) }
    end

    def post(uri, secret)
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{secret}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = '{}'
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    end
  end
end
