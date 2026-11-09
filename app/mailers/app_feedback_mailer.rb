# Notifies the feedback inbox (AppFeedback.config.notify_email, from ENV['FEEDBACK_EMAIL']) about
# new bug reports. Carries the message and build details, never the sender's email or the
# diagnostics; the admin page has the rest.
class AppFeedbackMailer < ApplicationMailer
  def new_bug(feedback)
    @feedback = feedback
    @admin_path = "#{Spree.admin_path.chomp('/')}/feedback/#{feedback.id}"
    from = Spree::Store.default&.mail_from_address.presence
    build = [feedback.platform, feedback.app_version, feedback.build_number && "(#{feedback.build_number})"].compact.join(' ')
    subject = "New bug report ##{feedback.id}"
    subject += ": #{build}" if build.present?
    message = mail(**{ to: AppFeedback.config.notify_email, subject: subject, from: from }.compact)
    # This mail only, whatever the app's global setting: the caller logs a failed delivery.
    message.raise_delivery_errors = true
    message
  end
end
