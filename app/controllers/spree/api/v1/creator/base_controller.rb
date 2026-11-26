module Spree
  module Api
    module V1
      module Creator
        # The creator portal API. Bearer required (401), and the creator role with an active
        # creator account (403 otherwise). A creator only ever sees their own records.
        class BaseController < Spree::Api::BaseController
          include Profiles::ApiResponses

          before_action :require_bearer_user
          before_action :require_creator

          private

          attr_reader :creator_account

          def require_creator
            @creator_account = Creators.active_account(current_api_user)
            render_error('forbidden', :forbidden) unless @creator_account
          end

          # Plain Ruby values from request params (JSON or form): nested params become hashes.
          def plain(value)
            case value
            when ActionController::Parameters then value.to_unsafe_h.to_h
            when Array then value.map { |item| plain(item) }
            else value
            end
          end
        end
      end
    end
  end
end
