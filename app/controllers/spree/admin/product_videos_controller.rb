module Spree
  module Admin
    # "Videos" tab on a product: /admin/products/:product_id/product_videos.
    # Admin only (Admin::BaseController#authorize_admin checks :admin on Spree::ProductVideo).
    class ProductVideosController < ResourceController
      before_action :load_product, only: :update_positions

      def update_positions
        ApplicationRecord.transaction do
          params.require(:positions).each do |id, index|
            @product.videos.find_by(id: id)&.set_list_position(index)
          end
        end

        respond_to do |format|
          format.js { head :ok }
          format.html { redirect_to location_after_save }
        end
      end

      private

      def model_class
        Spree::ProductVideo
      end

      def load_product
        @product ||= Spree::Product.friendly.find(params[:product_id])
      end

      def resource_not_found
        flash[:error] = flash_message_for(model_class.new, :not_found)
        redirect_to @product ? location_after_save : spree.admin_products_url
      end

      def parent
        load_product
      end

      def collection
        load_product.videos.with_attached_video.with_attached_poster
      end

      def find_resource
        load_product.videos.find(params[:id])
      end

      def build_resource
        load_product.videos.build
      end

      def permitted_resource_params
        return ActionController::Parameters.new unless params[:product_video].present?

        params.require(:product_video).permit(:alt, :video, :poster)
      end

      def location_after_save
        spree.admin_product_product_videos_url(@product)
      end

      def location_after_destroy
        spree.admin_product_product_videos_url(@product)
      end
    end
  end
end
