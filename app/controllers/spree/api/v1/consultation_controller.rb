module Spree
  module Api
    module V1
      class ConsultationController < Spree::Api::BaseController
        before_action :authenticate_user

        def show
          user = @current_api_user
          render json: {
            consultation_status: user.consultation_status,
            consultation_completed_at: user.consultation_completed_at,
            mdi_encounter_id: user.mdi_encounter_id,
            consultation_passed: user.consultation_passed?
          }
        end
      end
    end
  end
end
