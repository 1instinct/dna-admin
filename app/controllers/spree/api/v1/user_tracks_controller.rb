module Spree
  module Api
    module V1
      # The signed-in user's AI backing tracks. Bearer required. Tracks are private to their maker.
      #
      #   GET    /api/v1/user_tracks               own tracks, newest first (generating ones that
      #                                            are overdue are checked with the provider first)
      #   GET    /api/v1/user_tracks/:id
      #   POST   /api/v1/user_tracks               { style, moods[], bars, bpm, key, scale, timeSig }
      #                                            201 queued | 422 { error, fields } | 409 in_flight
      #                                            | 429 rate_limited | 402 quota | 503 busy (daily
      #                                            spend breaker) | 503 unavailable (no FAL_KEY)
      #   DELETE /api/v1/user_tracks/:id           204
      #   POST   /api/v1/user_tracks/:id/variation same request, new seed, one credit (as create)
      #   GET    /api/v1/user_tracks/:id/audio     302 to a short-lived signed URL (ready only)
      #   GET    /api/v1/user_tracks/styles        [{ id, label, bpmRange, defaultMoods, caption }]
      #   GET    /api/v1/user_tracks/moods         [{ id, label }]
      #   GET    /api/v1/user_tracks/quota         { remaining, monthlyFree, resetsAt }
      #
      # index, create and variation also send X-Quota-Remaining.
      class UserTracksController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user

        rescue_from(ActiveRecord::RecordNotFound) { render_not_found }

        def index
          reconcile
          tracks = own_tracks.newest_first.limit(100).with_attached_audio
          quota_header
          render json: tracks.map { |track| UserTracks::Presenter.call(track) }
        end

        def show
          render json: UserTracks::Presenter.call(track)
        end

        def create
          start(Spree::UserTrack.normalize_request(params.permit(*track_params).to_h))
        end

        def variation
          start(track.request.slice(*Spree::UserTrack::REQUEST_FIELDS))
        end

        def destroy
          UserTracks::Removal.call(track)
          head :no_content
        end

        # A 302 to a signed URL valid for UserTracks.config.signed_url_ttl. The Location header is
        # set by hand (redirect_to logs its target) and URL generation runs with DEBUG logging off
        # (ActiveStorage logs generated URLs), so the signed URL never reaches the log.
        def audio
          found = track
          return render_not_found unless found.ready? && found.audio.attached?

          url = UserTracks.quietly do
            ActiveStorage::Current.set(host: request.base_url) do
              found.audio.blob.url(expires_in: UserTracks.config.signed_url_ttl, disposition: :inline,
                                   filename: ActiveStorage::Filename.new("track-#{found.id}.flac"))
            end
          end
          response.headers['Location'] = url
          response.headers['Cache-Control'] = 'no-store'
          head :found
        end

        def styles
          render json: UserTracks::Styles.all
        end

        def moods
          render json: UserTracks::Styles.moods.map { |mood| mood.slice(:id, :label) }
        end

        def quota
          render json: { remaining: UserTracks::Quota.remaining(current_api_user),
                         monthlyFree: UserTracks.config.monthly_free,
                         resetsAt: UserTracks::Quota.resets_at.iso8601 }
        end

        private

        def track_params
          [:style, :bars, :bpm, :key, :scale, :timeSig, :time_sig, :moods, { moods: [] }]
        end

        def own_tracks
          Spree::UserTrack.kept.where(user_id: current_api_user.id)
        end

        def track
          @track ||= own_tracks.find(params[:id])
        end

        def start(request)
          new_track = Spree::UserTrack.new(user: current_api_user, source: 'ai', request: request)
          return render_record_errors(new_track, 'Track could not be made') unless new_track.valid?

          UserTracks::Start.call(new_track)
          quota_header
          render json: UserTracks::Presenter.call(new_track), status: :created
        rescue UserTracks::Start::InFlight
          render_error('in_flight', :conflict)
        rescue UserTracks::Start::RateLimited
          render_error('rate_limited', :too_many_requests)
        rescue UserTracks::Quota::Exhausted
          render_error('quota', :payment_required)
        rescue UserTracks::Start::Busy
          render_error('busy', :service_unavailable)
        rescue UserTracks::Start::Unavailable
          render_error('unavailable', :service_unavailable)
        end

        # Overdue tracks are checked with the provider before listing; a failure here never fails
        # the list.
        def reconcile
          UserTracks::Reconcile.call(current_api_user)
        rescue StandardError => e
          Rails.logger.error("[user_tracks] reconcile failed: #{e.class}")
        end

        def quota_header
          response.headers['X-Quota-Remaining'] = UserTracks::Quota.remaining(current_api_user).to_s
        end
      end
    end
  end
end
