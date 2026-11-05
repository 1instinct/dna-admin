module Spree
  module Api
    module V1
      # Public profiles by handle.
      #
      #   GET    /api/v1/profiles/:handle                auth optional (a valid bearer adds viewer state;
      #                                                  an invalid one is 401). 404 when missing, hidden,
      #                                                  deleted, locked, or a block exists either way.
      #   GET    /api/v1/profiles/handle_available?handle=  bearer. { available, reason }; 429 over the limit
      #   POST   /api/v1/profiles/:handle/follow         bearer. { following, followers_count }
      #   DELETE /api/v1/profiles/:handle/follow         bearer. 403 blocked, 404 missing, 422 self,
      #                                                  429 over the limit
      class ProfilesController < Spree::Api::BaseController
        include Profiles::ApiResponses

        # :cooldown is not a reason here: the name itself is free; the own profile carries
        # handle_changeable_at.
        AVAILABILITY_REASONS = { taken: 'taken', reserved: 'reserved', invalid: 'invalid', not_allowed: 'not_allowed' }.freeze

        skip_before_action :authenticate_user, only: :show
        before_action :reject_bad_credentials, only: :show
        before_action :require_bearer_user, except: :show
        before_action -> { enforce_rate_limit(:follow) }, only: %i[follow unfollow]
        before_action -> { enforce_rate_limit(:handle_available) }, only: :handle_available
        before_action :load_follow_target, only: %i[follow unfollow]

        def show
          profile = visible_profile(params[:handle])
          return render_not_found unless profile

          render json: presenter(profile).public_json
        end

        def handle_available
          result = Profiles::HandlePolicy.check(params[:handle], user: current_api_user)
          reason = AVAILABILITY_REASONS[result]
          render json: { available: reason.nil?, reason: reason }
        end

        def follow
          begin
            UserFollow.find_or_create_by!(follower_id: current_api_user.id, following_id: @target.id)
          rescue ActiveRecord::RecordNotUnique
            nil
          end
          render_follow_state
        end

        def unfollow
          UserFollow.where(follower_id: current_api_user.id, following_id: @target.id).delete_all
          render_follow_state
        end

        private

        def reject_bad_credentials
          render_error('unauthorized', :unauthorized) if api_credentials_present? && current_api_user.nil?
        end

        def load_follow_target
          profile = Spree::UserProfile.visible.find_by_handle(params[:handle])
          return render_not_found unless profile

          @target = profile.user
          if @target.id == current_api_user.id
            render_error("You can't follow yourself", :unprocessable_entity)
          elsif Spree::UserBlock.between?(current_api_user, @target)
            render_error("You can't follow this profile", :forbidden)
          end
        end

        def render_follow_state
          render json: {
            following: UserFollow.where(follower_id: current_api_user.id, following_id: @target.id).exists?,
            followers_count: UserFollow.where(following_id: @target.id).count
          }
        end
      end
    end
  end
end
