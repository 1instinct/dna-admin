module Spree
  module Api
    module V1
      # PATCH /api/v1/orders/current/affiliate { code }
      #
      # The current order is the one named by X-Spree-Order-Token (or ?order_token), else the
      # Bearer user's newest incomplete order in this store. A token for another signed-in user's
      # order is not found.
      #
      #   200 { attached: true }   the order is attributed to this code (now or before)
      #   200 { attached: false }  ignored: already attributed to another code, or self-referral
      #   204                      unknown code, or the affiliate isn't approved
      #   401                      invalid credentials
      #   404                      no current order
      #   422                      the order already completed
      class OrderAffiliatesController < Spree::Api::BaseController
        include Profiles::ApiResponses

        skip_before_action :authorize_for_order, :authenticate_user, raise: false
        before_action :reject_bad_credentials

        def update
          order = current_order
          return render_not_found unless order
          return render_error('order is already complete', :unprocessable_entity) if order.completed_at.present? || order.canceled?

          account = AffiliateAccount.approved.find_by_code(params[:code].is_a?(String) ? params[:code] : nil)
          return head :no_content unless account

          render json: { attached: Affiliates::Attribution.attach(order, account) }
        end

        private

        def reject_bad_credentials
          render_error('unauthorized', :unauthorized) if api_credentials_present? && current_api_user.nil?
        end

        def current_order
          user = viewer
          if order_token.present?
            order = Spree::Order.find_by(token: order_token.to_s, store_id: current_store.id)
            return nil if order.nil?
            return nil if user && order.user_id.present? && order.user_id != user.id

            order
          elsif user
            Spree::Order.incomplete.where(user_id: user.id, store_id: current_store.id, currency: current_currency)
                        .order(created_at: :desc).first
          end
        end
      end
    end
  end
end
