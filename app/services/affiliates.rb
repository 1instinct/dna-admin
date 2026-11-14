# Affiliate program: accounts, click tracking, order attribution, commissions and payouts.
#
# Settings live on Affiliates.config (see config/initializers/affiliates.rb for the ENV names).
module Affiliates
  class Config
    attr_writer :link_base_url, :visitor_salt
    attr_accessor :default_commission_bps, :cookie_days, :hold_days, :reserved_codes

    def initialize
      @default_commission_bps = 1000
      @cookie_days = 30
      @hold_days = 30
      # Codes nobody may take, on top of the profile module's reserved handles when present.
      @reserved_codes = %w[admin affiliate affiliates api help support shop store staff official]
    end

    # The storefront the affiliate links point at, without a trailing slash.
    def link_base_url
      value = defined?(@link_base_url) ? @link_base_url : ENV['AFFILIATE_LINK_BASE_URL'].presence || ENV['SITE_URL']
      value.to_s.chomp('/')
    end

    # Salt for visitor hashes. Derived from secret_key_base unless AFFILIATE_VISITOR_SALT is set.
    def visitor_salt
      @visitor_salt ||= ENV['AFFILIATE_VISITOR_SALT'].presence ||
                        Rails.application.key_generator.generate_key('affiliates.visitor_hash', 32).unpack1('H*')
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Tests use this to drop changed settings.
  def self.reset_config!
    @config = nil
  end
end
