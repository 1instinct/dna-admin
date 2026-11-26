module Spree
  module Admin
    class AppSettingsController < Spree::Admin::BaseController
      def index
        @settings = AppSetting.order(updated_at: :desc)
        @ios = AppSetting.latest_for('ios')
        @android = AppSetting.latest_for('android')
        @legacy = AppSetting.latest
      end

      def create
        @setting = AppSetting.new(setting_params)

        if @setting.save
          flash[:success] = "App setting v#{@setting.version} created."
          redirect_to admin_app_settings_path
        else
          flash[:error] = @setting.errors.full_messages.join(', ')
          redirect_to admin_app_settings_path
        end
      end

      def destroy
        setting = AppSetting.find(params[:id])
        setting.destroy
        flash[:success] = 'App setting deleted.'
        redirect_to admin_app_settings_path
      end

      private

      def setting_params
        params.require(:app_setting).permit(:name, :platform, :version, :build, :allow_ahead_of_store)
      end
    end
  end
end
