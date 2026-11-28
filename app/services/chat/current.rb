module Chat
  # Per-request values (reset after every request): the request's base URL, for absolute
  # attachment and image URLs in payloads built outside a controller (the admin app adapters).
  class Current < ActiveSupport::CurrentAttributes
    attribute :base_url
  end
end
