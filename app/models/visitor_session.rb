# One visit to the storefront, kept alive by the widget's pings (Visitors::Tracker). A session
# ends after Visitors.config.session_window without a ping; the next ping starts a new one.
class VisitorSession < ApplicationRecord
  DEVICES = %w[mobile tablet desktop].freeze

  belongs_to :contact
  belongs_to :order, class_name: 'Spree::Order', optional: true
  # page_views is the column counting them.
  has_many :pages, -> { order(created_at: :desc, id: :desc) }, class_name: 'VisitorPageView', dependent: :delete_all
  has_many :conversations, class_name: 'ThreadTable', dependent: :nullify

  validates :token, presence: true, uniqueness: true
  validates :device, inclusion: { in: DEVICES }, allow_nil: true

  scope :online, ->(now = Time.current) { where('visitor_sessions.last_seen_at >= ?', now - Visitors.config.online_window) }
  scope :offline, ->(now = Time.current) { where('visitor_sessions.last_seen_at < ?', now - Visitors.config.online_window) }
  scope :live, ->(now = Time.current) { where('visitor_sessions.last_seen_at >= ?', now - Visitors.config.session_window) }
  scope :recent_first, -> { order(last_seen_at: :desc, id: :desc) }

  def online?(now = Time.current)
    last_seen_at.present? && last_seen_at >= now - Visitors.config.online_window
  end

  # Still within the session window: the next ping extends it.
  def live?(now = Time.current)
    last_seen_at.present? && last_seen_at >= now - Visitors.config.session_window
  end

  # The linked order while it is still a cart: not completed, in a pre-payment checkout state.
  def cart
    order if order && order.completed_at.nil? && Visitors::CART_STATES.include?(order.state)
  end
end
