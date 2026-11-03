module Spree
  module Api
    module V1
      # The signed-in user's blocks. Bearer required.
      #
      #   GET    /api/v1/blocks           200 [{ handle, name, avatar }] (newest first)
      #   POST   /api/v1/blocks { handle } 201 { handle, name, avatar } (idempotent); 404 unknown; 422 self
      #   DELETE /api/v1/blocks/:handle   204; 404 when the user has no such block
      class BlocksController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user

        def index
          blocks = Spree::UserBlock.where(blocker_id: current_api_user.id).order(created_at: :desc, id: :desc)
          profiles = Spree::UserProfile.where(user_id: blocks.map(&:blocked_id)).index_by(&:user_id)
          list = blocks.map { |block| profiles[block.blocked_id] }.compact.map { |p| presenter(p).identity_json }
          render json: list
        end

        def create
          handle = params.require(:handle)
          profile = blockable_profile(handle)
          return render_not_found unless profile
          return render_error("You can't block yourself", :unprocessable_entity) if profile.user_id == current_api_user.id

          Spree::UserBlock.block!(current_api_user, profile.user)
          render json: presenter(profile).identity_json, status: :created
        end

        def destroy
          profile = Spree::UserProfile.find_by_handle(params[:handle])
          block = profile && Spree::UserBlock.find_by(blocker_id: current_api_user.id, blocked_id: profile.user_id)
          return render_not_found unless block

          block.destroy!
          head :no_content
        end

        private

        # Any live user's profile (hidden ones included, so people can block them too).
        def blockable_profile(handle)
          Spree::UserProfile.with_handle.joins(:user).where(Spree::User.table_name => { deleted_at: nil })
                            .where('lower(handle) = ?', Profiles::HandlePolicy.normalize(handle)).first
        end
      end
    end
  end
end
