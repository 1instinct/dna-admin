# Absolute links and images in email need this app's public address: email can't use paths.
# ADMIN_URL is that address, e.g. https://admin.example.com (scheme required). Without it, emails
# still send, but product images, the store logo and the background pattern are left out.
#
# Sets the URL host for routes (ActiveStorage representation URLs, url_for), for mailers, and the
# mailer asset host (image_tag / image_url in mail views).
admin_url = ENV['ADMIN_URL'].to_s.strip.chomp('/')

if admin_url.match?(%r{\Ahttps?://[^/\s]+\z})
  uri = URI.parse(admin_url)
  url_options = { host: uri.host, protocol: uri.scheme }
  url_options[:port] = uri.port unless [80, 443].include?(uri.port)

  Rails.application.routes.default_url_options.merge!(url_options)
  Rails.application.config.action_mailer.default_url_options = url_options
  Rails.application.config.action_mailer.asset_host = admin_url
  ActionMailer::Base.default_url_options = url_options
  ActionMailer::Base.asset_host = admin_url
elsif admin_url.present?
  Rails.logger.warn("[mailer] ADMIN_URL #{admin_url.inspect} isn't an absolute URL like https://admin.example.com; ignored")
end
