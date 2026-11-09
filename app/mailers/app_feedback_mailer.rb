# Notifies the feedback inbox (AppFeedback.config.notify_email, from ENV['FEEDBACK_EMAIL']) about
# new bug reports. Carries the message and build details, never the sender's email or the
# diagnostics; the admin page has the rest.
class AppFeedbackMailer < ApplicationMailer
  def new_bug(feedback)
    @feedback = feedback
    @admin_link = admin_link(feedback)
    from = Spree::Store.default&.mail_from_address.presence
    build = [feedback.platform, feedback.app_version, feedback.build_number && "(#{feedback.build_number})"].compact.join(' ')
    subject = "New bug report ##{feedback.id}"
    subject += ": #{build}" if build.present?
    message = mail(**{ to: AppFeedback.config.notify_email, subject: subject, from: from }.compact)
    # This mail only, whatever the app's global setting: the caller logs a failed delivery.
    message.raise_delivery_errors = true
    message
  end

  private

  # An absolute URL when the app sets a host in Rails.application.routes.default_url_options, else
  # the admin path. Neither the store's URL nor ActionMailer's default host is used: Spree's
  # mailers fill the latter with the former on their first send, and in a headless setup that is
  # the storefront's host, not the admin's.
  def admin_link(feedback)
    path = "#{Spree.admin_path.chomp('/')}/feedback/#{feedback.id}"
    options = (Rails.application.routes.default_url_options || {}).symbolize_keys
    return path if options[:host].blank?

    Spree::Core::Engine.routes.url_helpers.admin_app_feedback_url(feedback, **options.slice(:host, :port, :protocol))
  rescue StandardError
    path
  end
end
