# Storefront visitor tracking: who is on the storefront now, what they are looking at and what is
# in their cart. The widget pings POST /api/v1/storefront/visits; Visitors::Tracker keeps the
# sessions and page views; Visitors::Adapter serves them to the admin app.
module Visitors
  # Orders in these states with line items are carts.
  CART_STATES = %w[cart address delivery payment].freeze

  class Config
    attr_accessor :session_window, :online_window, :page_view_retention, :page_view_limit

    def initialize
      # A session ends after this long without a ping.
      @session_window = 30.minutes
      # A session is online when it pinged this recently.
      @online_window = 2.minutes
      # rake visitors:prune drops page views older than this.
      @page_view_retention = 30.days
      # Pages a session's detail lists, newest first.
      @page_view_limit = 50
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Tests use this to drop changed settings.
  def self.reset_config!
    @config = nil
  end

  # Deletes page views older than the retention, in batches; returns how many.
  def self.prune!(now: Time.current)
    cutoff = now - config.page_view_retention
    deleted = 0
    VisitorPageView.where('created_at < ?', cutoff).in_batches(of: 5000) { |batch| deleted += batch.delete_all }
    deleted
  end
end
