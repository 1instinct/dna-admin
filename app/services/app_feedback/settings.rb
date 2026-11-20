class AppFeedback < ApplicationRecord
  # AppFeedback.config. Reads ENV unless a value was set (tests set them directly).
  #
  # ENV:
  #   FEEDBACK_EMAIL                inbox that gets one email per `bug` report (none sent when unset)
  #   SENTRY_FEEDBACK_URL_TEMPLATE  "Open in Sentry" link on the admin page, with %{id} where the
  #                                 sentry_event_id goes, e.g. https://<org>.sentry.io/issues/?query=%{id}
  #                                 (no link when unset)
  class Settings
    attr_writer :notify_email, :sentry_url_template
    attr_accessor :rate_limits

    def initialize
      # Fixed windows, see AppFeedback::RateLimit. sender is the signed-in user, or the install
      # id when anonymous; ip is every request from one address.
      @rate_limits = {
        sender: { limit: 10, window: 24.hours },
        ip: { limit: 30, window: 24.hours }
      }
    end

    def notify_email
      defined?(@notify_email) ? @notify_email : ENV['FEEDBACK_EMAIL'].presence
    end

    def sentry_url_template
      template = defined?(@sentry_url_template) ? @sentry_url_template : ENV['SENTRY_FEEDBACK_URL_TEMPLATE'].presence
      template if template.to_s.match?(%r{\Ahttps?://}i)
    end
  end
end
