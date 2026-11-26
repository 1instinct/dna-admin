module Spree
  module Admin
    # Reviews > Review settings: the one Spree::ReviewSetting row, edited in place like the admin
    # theme. /admin/review_settings redirects to the edit form.
    class ReviewSettingsController < Spree::Admin::BaseController
      PERMITTED = %i[
        enabled store_reviews_enabled questions_enabled auto_publish photos_require_approval
        request_delay_days international_request_delay_days reminder_delay_days request_expiry_days
        points_per_review points_photo_bonus ai_summary_enabled ai_summary_min_reviews
      ].freeze

      before_action :load_settings

      def show
        redirect_to spree.edit_admin_review_settings_path
      end

      def edit; end

      def update
        if @settings.update(params.require(:review_setting).permit(*PERMITTED))
          flash[:success] = 'Review settings saved.'
          redirect_to spree.edit_admin_review_settings_path
        else
          flash.now[:error] = @settings.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def model_class
        Spree::ReviewSetting
      end

      def load_settings
        @settings = Spree::ReviewSetting.current
      end
    end
  end
end
