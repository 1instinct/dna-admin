# Error and performance reporting for the admin, CMS and API.
#
# Off unless SENTRY_DSN is set, so development, test and any deploy without a DSN send nothing.
# Each product sets its own DSN (a Rails project in its Sentry organization) on its host, e.g.
# `heroku config:set SENTRY_DSN=https://…`. Optional: SENTRY_ENVIRONMENT, SENTRY_TRACES_SAMPLE_RATE.
if ENV['SENTRY_DSN'].present?
  # Spree API credentials travel in these headers and query parameters; Rails' parameter filter
  # and send_default_pii don't know their names.
  secret_headers = %w[X-Spree-Token X-Spree-Order-Token X-Spree-Api-Key Authorization Cookie].freeze
  secret_params = /([?&](?:token|order_token|api_key|access_token|refresh_token|code)=)[^&#\s]*/i.freeze

  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.environment = ENV['SENTRY_ENVIRONMENT'] || Rails.env

    # Requests carry customer addresses, order contents and tokens: no bodies, cookies or IPs.
    config.send_default_pii = false

    # Traces are billed per event and the storefront API is busy; override per environment.
    config.traces_sample_rate = (ENV['SENTRY_TRACES_SAMPLE_RATE'] || 0.1).to_f

    # Ordinary 404s and bot traffic, not defects.
    config.excluded_exceptions += [
      'ActiveRecord::RecordNotFound',
      'ActionController::RoutingError',
      'ActionController::UnknownFormat',
      'ActionController::InvalidAuthenticityToken'
    ]

    # The deployed revision, so an issue can be traced to a release.
    config.release = ENV['HEROKU_SLUG_COMMIT'] || ENV['SOURCE_VERSION']

    config.before_send = lambda do |event, _hint|
      request = event.request
      if request
        headers = request.headers || {}
        secret_headers.each { |h| headers[h] = '[Filtered]' if headers.key?(h) }
        request.url = request.url.to_s.gsub(secret_params, '\1[Filtered]') if request.url
        if request.query_string.is_a?(String)
          request.query_string = "?#{request.query_string}".gsub(secret_params, '\1[Filtered]').delete_prefix('?')
        end
      end
      event
    end

    config.before_breadcrumb = lambda do |breadcrumb, _hint|
      url = breadcrumb.data.is_a?(Hash) ? breadcrumb.data[:url] || breadcrumb.data['url'] : nil
      breadcrumb.data[:url] = url.to_s.gsub(secret_params, '\1[Filtered]') if url
      breadcrumb
    end
  end
end
