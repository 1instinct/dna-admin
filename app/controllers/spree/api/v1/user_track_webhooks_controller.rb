module Spree
  module Api
    module V1
      # POST /api/v1/user_tracks/webhook/:token  fal's callback when a generation finishes.
      #
      # No auth: the token ("<track id>-<secret>", in the URL Rails gave fal) names the track and
      # its secret is compared in constant time. The webhook only triggers finalising: the body is
      # never read, and FinalizeJob fetches the status and result from fal with Rails' own key.
      # 200 { ok: true } (also for a deleted or already finished track, so fal stops retrying);
      # 404 for an unknown token.
      class UserTrackWebhooksController < Spree::Api::BaseController
        include Spree::Api::V1::UserAuthentication

        def create
          track = Spree::UserTrack.find_by_webhook_token(params[:token])
          return render json: { error: 'not_found' }, status: :not_found unless track

          UserTracks::FinalizeJob.perform_later(track.id) if track.generating? && track.deleted_at.nil?
          render json: { ok: true }
        end
      end
    end
  end
end
