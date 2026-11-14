require 'digest'

# One visit through an affiliate link. Stores the landing path (no query string), the referring
# host (no path or query) and a visitor hash: a salted SHA-256 of IP and user agent that changes
# every day, so visitors can be counted without storing raw IPs.
class AffiliateClick < ApplicationRecord
  PATH_MAX = 255

  belongs_to :affiliate_account

  def self.visitor_hash(ip:, user_agent:, date: Date.current)
    Digest::SHA256.hexdigest([Affiliates.config.visitor_salt, date.iso8601, ip.to_s, user_agent.to_s].join("\n"))
  end

  def self.referrer_host_for(referrer)
    return nil if referrer.blank?

    host = URI.parse(referrer.to_s.strip).host
    host.presence&.downcase&.slice(0, PATH_MAX)
  rescue URI::InvalidURIError
    nil
  end

  def self.landing_path_for(path)
    raw = path.to_s.strip
    return '/' if raw.empty?

    parsed = begin
      URI.parse(raw).path
    rescue URI::InvalidURIError
      raw.split(/[?#]/, 2).first
    end
    parsed = "/#{parsed}" unless parsed.to_s.start_with?('/')
    parsed[0, PATH_MAX]
  end
end
