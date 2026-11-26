module Spree
  module Api
    module V1
      class PushSubscriptionsController < Spree::Api::BaseController
        before_action :authenticate_user

        def create
          token = params[:token].to_s.strip
          platform = params[:platform].to_s.strip.downcase
          device_name = params[:device_name].to_s.strip.presence

          if token.blank? || !%w[ios android].include?(platform)
            render json: {
              response_code: 422,
              response_message: 'Token and valid platform (ios/android) are required.'
            }, status: :unprocessable_entity and return
          end

          subscription = PushSubscription.find_or_initialize_by(token: token)
          subscription.assign_attributes(
            user: current_api_user,
            platform: platform,
            device_name: device_name,
            enabled: true
          )

          if subscription.save
            render json: {
              response_code: 200,
              response_message: 'Push subscription registered.',
              response_data: {
                id: subscription.id,
                token: subscription.token,
                platform: subscription.platform
              }
            }
          else
            render json: {
              response_code: 422,
              response_message: subscription.errors.full_messages.join(', ')
            }, status: :unprocessable_entity
          end
        end

        def destroy
          subscription = PushSubscription.find_by(
            token: params[:token] || params[:id],
            user: current_api_user
          )

          if subscription&.destroy
            render json: { response_code: 200, response_message: 'Push subscription removed.' }
          else
            render json: { response_code: 404, response_message: 'Subscription not found.' }, status: :not_found
          end
        end

        private

        # current_api_user comes from Spree::Api::BaseController#load_user: a valid, unexpired,
        # unrevoked OAuth bearer token, else the X-Spree-Token api key. (The old local lookup
        # named Spree::OauthAccessToken, which doesn't exist on Spree 4.2, so every bearer request
        # that reached it raised NameError and returned 500.)
        def authenticate_user
          unless current_api_user
            render json: { response_code: 401, response_message: 'Unauthorized' }, status: :unauthorized
          end
        end
      end
    end
  end
end
