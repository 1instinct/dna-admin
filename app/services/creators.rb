# Creators: users who sell their own digital products. A user applies
# (Spree::CreatorApplication); an admin approves (Creators::Approver), which gives them the Spree
# role Creators.config.role_name and a Spree::CreatorAccount. The role is the authority; an
# is_creator column on users, when the app has one, is kept in step with it.
#
# Settings live on Creators.config; an app sets its own in a to_prepare block (see
# config/initializers/creators.rb).
module Creators
  class Config
    # default_share_bps: the creator's share of a sale, in basis points (7000 = 70%).
    # hold_days: days after an order completes before its earnings become payable.
    # marketplace_taxon_permalink: approved products are added to this taxon.
    # role_name: the Spree role that makes a user a creator.
    # shipping_category_name: the shipping category of creator products (created when missing).
    # max_samples: demo files an application may carry.
    # sales_rows_limit: rows returned by GET /api/v1/creator/sales.
    attr_accessor :default_share_bps, :hold_days, :marketplace_taxon_permalink, :role_name,
                  :shipping_category_name, :max_samples, :sales_rows_limit

    def initialize
      @default_share_bps = 7000
      @hold_days = 14
      @marketplace_taxon_permalink = 'marketplace'
      @role_name = 'creator'
      @shipping_category_name = 'Digital'
      @max_samples = 3
      @sales_rows_limit = 500
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Apps call this from a to_prepare block. The block is kept so reset_config! can replay it.
  def self.configure(&block)
    configurers << block
    block.call(config)
  end

  # Tests use this to drop settings they changed.
  def self.reset_config!
    @config = nil
    configurers.each { |block| block.call(config) }
  end

  def self.configurers
    @configurers ||= []
  end

  def self.creator?(user)
    user.present? && user.has_spree_role?(config.role_name)
  end

  def self.role
    Spree::Role.find_or_create_by!(name: config.role_name)
  end

  def self.marketplace_taxon
    permalink = config.marketplace_taxon_permalink.to_s
    permalink.empty? ? nil : Spree::Taxon.find_by(permalink: permalink)
  end

  def self.shipping_category
    Spree::ShippingCategory.find_or_create_by!(name: config.shipping_category_name)
  end

  # The account of an active creator (role and active account), else nil.
  def self.active_account(user)
    return unless creator?(user)

    Spree::CreatorAccount.active.find_by(user_id: user.id)
  end

  # { handle, name } of a product's creator, or nil for an ordinary product. The handle and name
  # come from the creator's profile (when it isn't hidden); the name falls back to the display
  # name of their approved application.
  def self.identity(product)
    user_identity(product&.creator_id)
  end

  def self.user_identity(user_id)
    return unless user_id

    profile = Spree::UserProfile.find_by(user_id: user_id, hidden_at: nil)
    name = profile&.name.presence ||
           Spree::CreatorApplication.where(user_id: user_id, status: 'approved').order(:reviewed_at).last&.display_name
    { handle: profile&.handle, name: name }
  end

  # An order number reduced to its last four characters: creators never see who bought.
  def self.mask_order_number(number)
    number = number.to_s
    "****#{number[-4..] || number}"
  end
end
