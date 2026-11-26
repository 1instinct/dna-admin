module Spree
  module Admin
    # Creators tab: the review queue of submitted creator products. The detail page plays the
    # preview and the draft's files and shows the manifest; approve, request changes or reject
    # (Creators::Reviewer).
    class CreatorReviewsController < Spree::Admin::BaseController
      PER_PAGE = 50

      before_action :load_product, except: :index

      def index
        @products = Spree::Product.creator_products.where(review_state: 'submitted').includes(:creator)
                                  .order(:submitted_at, :id).page(params[:page]).per(PER_PAGE)
      end

      def show
        master = @product.master
        @draft = Spree::DigitalAsset.draft.where(variant_id: master.id).order(id: :desc).first
        @live = master.live_digital_asset
        @files = @draft ? @draft.files.attachments.includes(:blob).order(:id) : []
        @image = master.images.first
        @identity = Creators.identity(@product)
      end

      def approve
        Creators::Reviewer.approve!(@product, try_spree_current_user, params[:review_note])
        flash[:success] = "#{@product.name} approved and on sale"
        redirect_to spree.admin_creator_reviews_path
      rescue Creators::Reviewer::Error => e
        flash[:error] = e.message
        redirect_to spree.admin_creator_review_path(@product)
      end

      def request_changes
        decide(:request_changes!, 'Changes requested')
      end

      def reject
        decide(:reject!, 'Product rejected')
      end

      private

      def decide(action, message)
        Creators::Reviewer.public_send(action, @product, try_spree_current_user, params[:review_note])
        flash[:success] = message
        redirect_to spree.admin_creator_reviews_path
      rescue Creators::Reviewer::Error => e
        flash[:error] = e.message
        redirect_to spree.admin_creator_review_path(@product)
      end

      def model_class
        Spree::Product
      end

      def load_product
        @product = Spree::Product.creator_products.find(params[:id])
      end
    end
  end
end
