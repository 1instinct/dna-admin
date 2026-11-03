# Notifies the moderation inbox (Profiles.config.moderation_email, from ENV['MODERATION_EMAIL'])
# about new content reports. Carries the report snapshot and the reporter's handle, never emails.
class ModerationMailer < ApplicationMailer
  def new_report(report)
    @report = report
    @snapshot = report.snapshot || {}
    @reporter_handle = report.reporter&.profile&.handle
    @admin_path = "#{Spree.admin_path.chomp('/')}/content_reports/#{report.id}"
    from = Spree::Store.default&.mail_from_address.presence
    mail(**{ to: Profiles.config.moderation_email,
             subject: "New report ##{report.id}: profile @#{@snapshot['handle']} (#{report.reason})",
             from: from }.compact)
  end
end
