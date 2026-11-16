module Spree
  module Api
    module V1
      # POST /api/v1/user_tracks/webhook?webhook_token=<token>  fal's callback when a generation
      # finishes.
      #
      # No auth: the token ("<track id>-<secret>", in the URL Rails gave fal) names the track and
      # its secret is compared in constant time. It is a query parameter so the request log shows
      # it as [FILTERED]. The webhook only triggers finalising: the body is never read (the token
      # is taken from the query string only), and FinalizeJob fetches the status and result from
      # fal with Rails' own key. 200 { ok: true } (also for a deleted or already finished track, so
      # fal stops retrying); 404 for an unknown token.
      #
      # fal's body carries the generated audio's URL, so this action logs no parameter values: the
      # request's parameter filter masks every key ("Parameters" shows [FILTERED] throughout).
      class UserTrackWebhooksController < Spree::Api::BaseController
        skip_before_action :authenticate_user

        ALL_PARAMETERS = [/./].freeze

        def create
          track = Spree::UserTrack.find_by_webhook_token(request.query_parameters['webhook_token'])
          return render json: { error: 'not_found' }, status: :not_found unless track

          UserTracks::FinalizeJob.perform_later(track.id) if track.generating? && track.deleted_at.nil?
          render json: { ok: true }
        end

        private

        def process_action(*)
          request.set_header('action_dispatch.parameter_filter', ALL_PARAMETERS)
          super
        end
      end
    end
  end
end
