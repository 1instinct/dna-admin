module Spree
  module Api
    module V1
      # The signed-in user's own profile. Bearer required.
      #
      #   GET    /api/v1/profile          200 own profile (nothing is created)
      #   PATCH  /api/v1/profile          { profile: { handle, name, bio, website, visibility } }
      #                                   200 own profile | 422 { error, fields }
      #   PUT    /api/v1/profile/avatar   multipart `avatar` (jpeg/png/webp <= 5 MB)
      #                                   200 own profile | 413 | 415 | 422
      #   DELETE /api/v1/profile/avatar   200 own profile
      class ProfileController < Spree::Api::BaseController
        include Profiles::ApiResponses

        PERMITTED = %i[handle name bio website visibility].freeze

        before_action :require_bearer_user

        def show
          render_own
        end

        def update
          attrs = params.require(:profile).permit(*PERMITTED)
          profile.assign_attributes(attrs)
          if profile.save
            render_own
          else
            render_record_errors(profile, 'Profile could not be saved')
          end
        rescue ActiveRecord::RecordNotUnique
          profile.errors.add(:handle, Spree::UserProfile::HANDLE_MESSAGES[:taken])
          render_record_errors(profile, 'Profile could not be saved')
        end

        def update_avatar
          Profiles::AvatarUpload.call(profile, params[:avatar])
          render_own
        rescue Profiles::AvatarUpload::Error => e
          render_error(e.message, e.status)
        rescue ActiveRecord::RecordInvalid
          render_record_errors(profile, 'Profile could not be saved')
        end

        def destroy_avatar
          profile.avatar.purge_later if profile.persisted? && profile.avatar.attached?
          render_own
        end

        private

        def profile
          @profile ||= current_api_user.profile || current_api_user.build_profile
        end

        def render_own
          render json: presenter(profile, viewer: current_api_user).own_json
        end
      end
    end
  end
end
