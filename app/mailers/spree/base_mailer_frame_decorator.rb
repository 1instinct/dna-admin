# Spree's mailers render with layouts/spree/base_mailer, which this app overrides to use the shared
# email frame (shared/_email_frame); the frame's helpers come from StoreMailerHelper.
# Loaded by the to_prepare decorator glob; adding the same helper again changes nothing.
Spree::BaseMailer.helper StoreMailerHelper
