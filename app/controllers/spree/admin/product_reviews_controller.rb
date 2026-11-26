module Spree
  module Admin
    # The "Reviews" tab on a product: /admin/products/:product_id/reviews.
    #
    # Shows the product's rating stats for one scope (retail, the public default; wholesale; or all
    # channels), the AI summary (always built from retail reviews and stored on the retail
    # ReviewStat row) with a Hide/Show switch, and the product's reviews in every status. Each
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

      private

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
