module Visitors
  # Handles the widget's visit pings (POST /api/v1/storefront/visits): finds the contact's live
  # session or starts one (a session ends after Visitors.config.session_window without a ping),
  # records a page view when the page changed, and links the cart from the order token.
  #
  #   Visitors::Tracker.new(contact, request_info).ping(url:, title:, referrer:, utm:, order_token:)
  #
  # request_info: { user_agent:, ip:, country: } (Visitors::Tracker.request_info(request) builds it).
  class Tracker
    URL_MAX = 2048
    TITLE_MAX = 255
    UTM_MAX = 255

    TABLET = /iPad|Tablet|Kindle|Silk|PlayBook|Nexus (7|9|10)|SM-T\d|Android(?!.*Mobile)/i.freeze
    MOBILE = /Mobi|iPhone|iPod|Android.*Mobile|Windows Phone|BlackBerry|BB10|Opera Mini|IEMobile/i.freeze

    attr_reader :contact, :request_info

    def self.request_info(request)
      {
        user_agent: request.user_agent.to_s,
        ip: request.remote_ip,
        country: country_from(request.headers['CF-IPCountry'].presence || request.headers['X-Country'].presence)
      }
    end

    def initialize(contact, request_info = {})
      @contact = contact
      @request_info = request_info || {}
    end

    # Returns the session.
    # The cart is the order token's (a guest cart), else the signed-in user's current cart.
    def ping(url:, title: nil, referrer: nil, utm: nil, order_token: nil, user: nil, now: Time.current)
      url = clip(url, URL_MAX)
      title = clip(title, TITLE_MAX)
      utm = clean_utm(utm)
      order = cart_from(order_token) || user_cart(user)

      session = nil
      VisitorSession.transaction do
        session = live_session(now) || start_session(referrer, utm, now)
        session.with_lock do
          new_page = url.present? && url != session.current_url
          session.current_url = url if url.present?
          session.current_title = title if new_page || title.present?
          session.last_seen_at = now
          session.order = order if order
          fill_utm(session, utm)
          session.page_views += 1 if new_page
          session.save!
          VisitorPageView.create!(visitor_session: session, url: url, title: title, created_at: now) if new_page
        end
        contact.update_columns(last_seen_at: now, updated_at: now)
      end
      session
    end

    # The contact's session still within the window.
    def live_session(now = Time.current)
      contact.visitor_sessions.live(now).recent_first.first
    end

    # mobile, tablet or desktop from the user agent.
    def self.device_for(user_agent)
      ua = user_agent.to_s
      return 'desktop' if ua.blank?
      return 'tablet' if TABLET.match?(ua)
      return 'mobile' if MOBILE.match?(ua)

      'desktop'
    end

    # IPv4 to its /24, IPv6 to its /48; nil for anything unreadable.
    def self.truncate_ip(ip)
      return if ip.blank?

      addr = IPAddr.new(ip.to_s)
      addr = addr.native if addr.ipv4_mapped?
      (addr.ipv4? ? addr.mask(24) : addr.mask(48)).to_s
    rescue IPAddr::Error, ArgumentError
      nil
    end

    # Two-letter ISO country codes only (Cloudflare sends XX for unknown and T1 for Tor).
    def self.country_from(value)
      code = value.to_s.strip.upcase
      code if code.match?(/\A[A-Z]{2}\z/) && !%w[XX T1].include?(code)
    end

    private

    def start_session(referrer, utm, now)
      contact.visitor_sessions.create!(
        token: SecureRandom.urlsafe_base64(18), started_at: now, last_seen_at: now,
        referrer: clip(referrer, URL_MAX), utm_source: utm[:source], utm_medium: utm[:medium], utm_campaign: utm[:campaign],
        user_agent: clip(request_info[:user_agent], 1024), device: self.class.device_for(request_info[:user_agent]),
        ip: self.class.truncate_ip(request_info[:ip]), country: request_info[:country], page_views: 0
      )
    end

    def fill_utm(session, utm)
      return if utm.values.none?(&:present?) || session.utm_source.present? || session.utm_medium.present? || session.utm_campaign.present?

      session.utm_source = utm[:source]
      session.utm_medium = utm[:medium]
      session.utm_campaign = utm[:campaign]
    end

    # An incomplete order with this token: the visitor's cart.
    def cart_from(order_token)
      return if order_token.blank? || !order_token.is_a?(String)

      Spree::Order.where(completed_at: nil).find_by(token: order_token)
    end

    # The signed-in user's newest incomplete order with items.
    def user_cart(user)
      return unless user&.persisted?

      Spree::Order.where(user_id: user.id, completed_at: nil, state: Visitors::CART_STATES)
                  .where('spree_orders.item_count > 0').order(updated_at: :desc).first
    end

    def clean_utm(utm)
      utm = utm.to_unsafe_h if utm.respond_to?(:to_unsafe_h)
      utm = {} unless utm.is_a?(Hash)
      utm = utm.symbolize_keys
      { source: clip(utm[:source], UTM_MAX), medium: clip(utm[:medium], UTM_MAX), campaign: clip(utm[:campaign], UTM_MAX) }
    end

    def clip(value, max)
      return unless value.is_a?(String) || value.is_a?(Numeric)

      text = value.to_s.delete("\u0000").strip
      text.presence && text[0, max]
    end
  end
end
