module Feeds
  # GET /feeds/google/product_reviews.xml: the Google Product Review Feed (schema v2.4) for
  # Merchant Center. Public, outside /api. Contract: docs/plans/2026-11-26-reviews-api-contract.md,
  # "M8 Google product review feed".
  #
  # 404 while reviews are switched off. The XML is cached for an hour (Rails.cache, keyed on the
  # included reviews' count and latest updated_at, so an edit shows up at once) and sent with a
  # one-hour Cache-Control. Links point at the storefront (SITE_URL); without it the feed is 503.
  class GoogleProductReviewsController < ActionController::Base
    CACHE_TTL = 1.hour

    def show
      return head(:not_found) unless Spree::ReviewSetting.current.enabled

      @feed = Reviews::GoogleFeed.new(site_url: ENV['SITE_URL'])
      if @feed.site_url.blank?
        Rails.logger.error('[reviews] Google review feed: SITE_URL is not set')
        return head(:service_unavailable)
      end

      xml = Rails.cache.fetch(@feed.cache_key, expires_in: CACHE_TTL) do
        render_to_string(template: 'feeds/google_product_reviews/show', formats: [:xml], layout: false)
      end
      expires_in CACHE_TTL, public: true
      render xml: xml
    end
  end
end
