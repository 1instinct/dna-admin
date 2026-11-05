# Serve product videos with Content-Disposition: inline. This must go through the app config:
# Active Storage copies config.active_storage.content_types_allowed_inline into
# ActiveStorage.content_types_allowed_inline in an after_initialize hook, which would
# overwrite a direct change to ActiveStorage.content_types_allowed_inline made here.
Rails.application.config.active_storage.content_types_allowed_inline =
  Array(Rails.application.config.active_storage.content_types_allowed_inline) | %w[video/mp4 video/webm]
