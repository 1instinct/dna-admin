# AI backing tracks (app/services/user_tracks.rb holds UserTracks.config).
#
# The generator's webhook URL carries the track's token as ?webhook_token=; keep it out of the
# request log (Rails logs the path with filtered query parameters).
Rails.application.config.filter_parameters += %i[webhook_token]
