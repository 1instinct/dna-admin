# A page a visitor opened during a session. Kept for Visitors.config.page_view_retention
# (`rake visitors:prune`).
class VisitorPageView < ApplicationRecord
  belongs_to :visitor_session

  validates :url, presence: true
end
