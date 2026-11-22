module UserTracks
  # The API's JSON for a track:
  #   { id, status, title, request, profile, loop, keyNote, error, creditRefunded, createdAt, readyAt }
  # profile and loop are null until the track is ready; error is plain words for a failed track.
  module Presenter
    module_function

    def call(track)
      ready = track.ready?
      {
        id: track.id.to_s,
        status: track.status,
        title: track.title,
        request: track.request,
        profile: ready ? track.profile : nil,
        loop: ready ? track.loop_info : nil,
        keyNote: ready ? track.profile&.dig('keyNote') : nil,
        error: track.failed? ? track.error : nil,
        creditRefunded: track.credit_refunded_at.present?,
        createdAt: track.created_at&.utc&.iso8601,
        readyAt: track.ready_at&.utc&.iso8601
      }
    end
  end
end
