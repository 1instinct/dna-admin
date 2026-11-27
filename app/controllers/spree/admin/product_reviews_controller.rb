module Spree
  module Admin
    # The "Reviews" tab on a product: /admin/products/:product_id/reviews.
    #
    # Shows the product's rating stats for one scope (retail, the public default; wholesale; or all
    # channels), the AI summary (always built from retail reviews and stored on the retail
    # ReviewStat row) with Hide/Show and Regenerate, and the product's reviews in every status. Each
    # review links to its page in the moderation queue (Spree::Admin::ReviewsController).
    class ProductReviewsController < Spree::Admin::BaseController
      PER_PAGE = 25

      helper 'spree/admin/reviews'

      before_action :load_product

      def index
        @scope = Spree::ReviewStat::SCOPES.include?(params[:scope]) ? params[:scope] : 'retail'
        @stat = Spree::ReviewStat.for(@product, @scope)
        @summary_stat = @scope == 'retail' ? @stat : Spree::ReviewStat.for(@product, 'retail')
        @attributes_by_key = Spree::ReviewAttribute.where(key: @stat.attribute_averages.keys).index_by(&:key)
        @settings = Spree::ReviewSetting.current

        reviews = Spree::Review.where(reviewable: @product).in_scope(@scope)
        @status_counts = reviews.group(:status).count
        @reviews = reviews.newest_first.page(params[:page]).per(PER_PAGE)
      end

      # Hides the AI summary from the product page, or shows it again. Hiding is logged (who and
      # when), as the compliance notes in the design doc require.
      def toggle_ai_summary
        stat = Spree::ReviewStat.for(@product, 'retail')
        if stat.new_record? || stat.ai_summary.blank?
          flash[:error] = 'This product has no AI summary yet.'
        else
          hidden = !stat.ai_summary_hidden
          stat.update!(ai_summary_hidden: hidden)
          Rails.logger.info(
            "[reviews] AI summary #{hidden ? 'hidden' : 'shown'} for product #{@product.id} " \
            "by admin user #{spree_current_user&.id} at #{Time.current.utc.iso8601}"
          )
          flash[:success] = hidden ? 'AI summary hidden from the product page.' : 'AI summary shown on the product page again.'
        end
        redirect_to spree.admin_product_product_reviews_path(@product, scope: scope_param)
      end

      # Regenerate: marks the AI summary stale (Reviews::AiSummaries) and asks the storefront to
      # write stale summaries now (Reviews::SummaryTrigger, on a thread: the storefront answers
      # only once the batch is written). The new summary replaces the old one when it arrives.
      def regenerate_ai_summary
        level, message = regenerate_result
        flash[level] = message
        redirect_to spree.admin_product_product_reviews_path(@product, scope: scope_param)
      end

      private

      def regenerate_result
        settings = Spree::ReviewSetting.current
        stat = Spree::ReviewStat.for(@product, 'retail')
        unless settings.ai_summary_enabled
          return [:error, 'AI summaries are switched off. Turn on "Write AI summaries" in Review settings first.']
        end
        if stat.ai_summary_hidden
          return [:error, 'This AI summary is hidden. Show it on the product page before regenerating it.']
        end
        if stat.reviews_count < settings.ai_summary_min_reviews
          return [:error, "A summary needs at least #{settings.ai_summary_min_reviews} published retail reviews with text; " \
                          "this product has #{stat.reviews_count}."]
        end

        Reviews::AiSummaries.request_regeneration!(@product)
        Rails.logger.info("[reviews] AI summary regeneration requested for product #{@product.id} by admin user #{spree_current_user&.id}")
        unless Reviews::SummaryTrigger.configured?
          return [:error, "Marked for regeneration, but the storefront can't be asked to write it: SITE_URL and " \
                          'INTERNAL_CRON_SECRET must both be set on dna-admin (INTERNAL_CRON_SECRET matching the storefront\'s). ' \
                          'Until then nothing will rewrite it.']
        end

        Reviews::SummaryTrigger.call_in_background
        [:success, 'Regenerating the AI summary. The new one should appear here in a minute or two; reload the page to see it. ' \
                   'Until then the current summary stays on the product page.']
      end


      def model_class
        Spree::Review
      end

      def load_product
        @product = Spree::Product.with_deleted.friendly.find(params[:product_id])
      rescue ActiveRecord::RecordNotFound
        flash[:error] = 'Product not found.'
        redirect_to spree.admin_products_path
      end

      def scope_param
        params[:scope] if Spree::ReviewStat::SCOPES.include?(params[:scope]) && params[:scope] != 'retail'
      end
    end
  end
end
