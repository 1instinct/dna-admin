require 'pusher'

channels_client =
    Pusher::Client.new(
        app_id: 'dna-api-id',
        key: 'dna-api-key',
        secret: 'dna-api-secret',
        cluster: 'dna-api-cluster',
        use_tls: true
    )

:cluster


{
  "name": "client_event",
  "channel": "name of the channel the event was published on",
  "event": "name of the event",
  "data": "data associated with the event",
  "socket_id": "socket_id of the sending socket",
  "user_id": "user_id associated with the sending socket" # Only for presence channels
}