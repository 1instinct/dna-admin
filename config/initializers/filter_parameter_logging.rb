# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += %i[password]
# In-app purchase payloads (store-signed JWS, Play purchase tokens, push tokens).
Rails.application.config.filter_parameters += %i[signed_payload signedPayload purchase_token token]
