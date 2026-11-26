# The post-purchase review request emails (M4). Design: docs/plans/2026-11-26-product-reviews-design.md,
# "Review request email flow".
#
#   ReviewRequests::Schedule   on ship: one Spree::ReviewRequest per order, send_after = shipped_at + delay
#   ReviewRequests::Dispatch   the hourly `rake reviews:dispatch`: send, remind, expire, complete
#   ReviewRequests::Backfill   `rake reviews:backfill[days]`: requests for orders shipped before launch
#   ReviewRequests::RateLimit  submissions per email link (X-Review-Token)
#
# There is no persistent job queue (ActiveJob is :async), so nothing is enqueued: all state lives on
# the request row and the rake task moves it along. Mail is sent inline (deliver_now).
module ReviewRequests
end
