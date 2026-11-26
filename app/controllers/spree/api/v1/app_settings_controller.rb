module Spree
  module Api
    module V1
      class AppSettingsController < ActionController::API
        # GET /api/v1/app_settings/latest[?platform=ios|android]
        # Without a known platform (older app builds) this is the platform-blind gate.
        def latest
          setting = AppSetting.latest_for(params[:platform])
          render json: {
            response_code: 200,
            response_data: {
              name: setting.name,
              platform: setting.platform,
              version: setting.version,
              build: setting.build
            }
          }
        end
      end
    end
  end
end
