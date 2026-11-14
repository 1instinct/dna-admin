# A user's affiliate account: the application, the ref code and the commission terms.
#
# code: 4-24 of a-z, 0-9 and -, stored lowercase, unique; defaults to the profile handle
#       (underscores become dashes). Reserved handles and other users' handles are refused.
# status: pending | approved | rejected | suspended. Only approved accounts earn.
# commission_bps: nil means Affiliates.config.default_commission_bps.
# application: { website, audience, channels[], message }.
class AffiliateAccount < ApplicationRecord
  STATUSES = %w[pending approved rejected suspended].freeze
  CODE_FORMAT = /\A[a-z0-9-]{4,24}\z/.freeze
  APPLICATION_KEYS = %w[website audience channels message].freeze

  belongs_to :user, class_name: Spree.user_class.to_s, inverse_of: :affiliate_account
  belongs_to :reviewed_by, class_name: Spree.user_class.to_s, optional: true
  has_many :clicks, class_name: 'AffiliateClick', dependent: :delete_all
  has_many :commissions, class_name: 'AffiliateCommission', dependent: :restrict_with_error
  has_many :payouts, class_name: 'AffiliatePayout', dependent: :restrict_with_error
  has_many :orders, class_name: 'Spree::Order', dependent: :nullify

  attribute :cookie_days, :integer, default: -> { Affiliates.config.cookie_days }

  before_validation :normalize_code
  before_validation :default_code, on: :create

  validates :user_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :code, presence: true, format: { with: CODE_FORMAT, message: 'must be 4-24 letters, digits or dashes' },
                   uniqueness: { case_sensitive: false }
  validates :commission_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000 },
                             allow_nil: true
  validates :cookie_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  validates :payout_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :code_not_reserved, if: -> { code.present? && will_save_change_to_code? }
  validate :application_shape

  STATUSES.each do |name|
    scope name, -> { where(status: name) }
    define_method("#{name}?") { status == name }
  end

  def self.normalize_code(code)
    code.to_s.strip.downcase
  end

  def self.find_by_code(code)
    normalized = normalize_code(code)
    return nil if normalized.empty?

    find_by(code: normalized)
  end

  # Whether `code` can be taken by `user`: valid, not reserved, not another user's affiliate code
  # or profile handle.
  def self.code_available?(code, user:)
    code = normalize_code(code)
    return false unless CODE_FORMAT.match?(code)
    return false if code_refused?(code)
    return false if where(code: code).where.not(user_id: user&.id).exists?
    return false if handle_of_another_user?(code, user)

    true
  end

  def self.code_refused?(code)
    return true if Affiliates.config.reserved_codes.include?(code)
    return false unless defined?(Profiles::HandlePolicy)

    [code, code.tr('-', '_')].uniq.any? { |c| Profiles::HandlePolicy.reserved?(c) } ||
      !Profiles::ContentFilter.allowed?(code.tr('-', '_'), mode: :handle)
  end

  def self.handle_of_another_user?(code, user)
    return false unless defined?(Spree::UserProfile)

    scope = Spree::UserProfile.where('lower(handle) = ?', code.tr('-', '_'))
    scope = scope.where.not(user_id: user.id) if user&.id
    scope.exists?
  end

  def effective_commission_bps
    commission_bps || Affiliates.config.default_commission_bps
  end

  # Earns commission on orders completed now.
  def earning?
    approved?
  end

  def link(path = '/')
    path = "/#{path}" unless path.to_s.start_with?('/')
    separator = path.include?('?') ? '&' : '?'
    "#{Affiliates.config.link_base_url}#{path}#{separator}ref=#{code}"
  end

  # { clicks, orders, conversion, pending, approved, paid, currency }, all time or within `range`
  # (by created_at). orders counts commissions that are not void.
  def totals(range = nil)
    click_scope = clicks
    commission_scope = commissions
    if range
      click_scope = click_scope.where(created_at: range)
      commission_scope = commission_scope.where(created_at: range)
    end

    click_count = click_scope.count
    sums = commission_scope.group(:state).sum(:amount)
    order_count = commission_scope.where.not(state: 'void').count
    {
      clicks: click_count,
      orders: order_count,
      conversion: click_count.zero? ? 0.0 : (order_count.to_f / click_count).round(4),
      pending: money(sums['pending']),
      approved: money(sums['approved']),
      paid: money(sums['paid']),
      currency: currency
    }
  end

  def currency
    commissions.order(created_at: :desc).limit(1).pluck(:currency).first ||
      Spree::Store.default&.default_currency.presence || 'USD'
  end

  def application_data
    (application || {}).slice(*APPLICATION_KEYS)
  end

  private

  def money(value)
    (value || 0).to_d.round(2).to_f
  end

  def normalize_code
    self.code = self.class.normalize_code(code) unless code.nil?
  end

  def default_code
    return if code.present? || user.nil?

    handle = user.respond_to?(:profile) ? user.profile&.handle : nil
    candidate = handle.to_s.downcase.tr('_', '-')[0, 24]
    self.code = candidate if CODE_FORMAT.match?(candidate) && !self.class.where(code: candidate).exists?
  end

  def code_not_reserved
    errors.add(:code, 'is not available') if self.class.code_refused?(code) || self.class.handle_of_another_user?(code, user)
  end

  def application_shape
    unless application.is_a?(Hash)
      errors.add(:application, 'must be an object')
      return
    end

    data = application
    errors.add(:application, 'website is too long') if data['website'].to_s.length > 255
    errors.add(:application, 'audience is too long') if data['audience'].to_s.length > 1000
    errors.add(:application, 'message is too long') if data['message'].to_s.length > 2000
    channels = data['channels']
    return if channels.nil?

    unless channels.is_a?(Array) && channels.length <= 20 && channels.all? { |c| c.is_a?(String) && c.length <= 60 }
      errors.add(:application, 'channels must be a list of up to 20 short strings')
    end
  end
end
