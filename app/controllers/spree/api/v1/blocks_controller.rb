module Spree
  module Api
    module V1
      # The signed-in user's blocks. Bearer required.
      #
      #   GET    /api/v1/blocks           200 [{ handle, name, avatar }] (newest first)
      #   POST   /api/v1/blocks { handle } 201 { handle, name, avatar } (idempotent); 404 unknown; 422 self
      #   DELETE /api/v1/blocks/:handle   204; 404 when the user has no such block
      #   POST and DELETE answer 429 over the limit.
      #   name and avatar are null when the profile is hidden or locked, or its owner blocked the caller.
      class BlocksController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user
        before_action -> { enforce_rate_limit(:block) }, only: %i[create destroy]

        def index
          blocks = Spree::UserBlock.where(blocker_id: current_api_user.id).order(created_at: :desc, id: :desc)
          profiles = Spree::UserProfile.where(user_id: blocks.map(&:blocked_id)).index_by(&:user_id)
          shown = shown_profile_ids(profiles.values)
          list = blocks.map { |block| profiles[block.blocked_id] }.compact.map { |p| block_json(p, shown) }
          render json: list
        end

        def create
          handle = params.require(:handle)
          profile = blockable_profile(handle)
          return render_not_found unless profile
          return render_error("You can't block yourself", :unprocessable_entity) if profile.user_id == current_api_user.id

          Spree::UserBlock.block!(current_api_user, profile.user)
          render json: block_json(profile, shown_profile_ids([profile])), status: :created
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
                            .by_handle(handle).first
        end

        # Name and avatar only for profiles the caller could see anyway (GET /profiles/:handle
        # aside from the caller's own block): visible, and the owner hasn't blocked the caller.
        # Otherwise only the handle, which the caller already knows.
        def block_json(profile, shown_ids)
          return presenter(profile).identity_json if shown_ids.include?(profile.id)

          { handle: profile.handle, name: nil, avatar: nil }
        end

        def shown_profile_ids(profiles)
          return Set.new if profiles.empty?

          blocking_me = Spree::UserBlock.where(blocker_id: profiles.map(&:user_id), blocked_id: current_api_user.id)
                                        .pluck(:blocker_id)
          Set.new(Spree::UserProfile.visible.where(id: profiles.map(&:id))
                                    .where.not(user_id: blocking_me).pluck(:id))
        end
      end
    end
  end
end
