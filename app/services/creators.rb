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
    # min_price: the lowest price a creator may set (free products are admin-only); a number, or a
    #   Hash of currency => number with an optional "default" key.
    attr_accessor :default_share_bps, :hold_days, :marketplace_taxon_permalink, :role_name,
                  :shipping_category_name, :max_samples, :sales_rows_limit, :min_price

    def initialize
      @default_share_bps = 7000
      @hold_days = 14
      @marketplace_taxon_permalink = 'marketplace'
      @role_name = 'creator'
      @shipping_category_name = 'Digital'
      @max_samples = 3
      @sales_rows_limit = 500
      @min_price = BigDecimal('0.5')
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

    identities_for([user_id])[user_id]
  end

  # { user_id => { handle, name } } for many creators in two queries (storefront listings).
  def self.identities_for(user_ids)
    ids = Array(user_ids).compact.uniq
    return {} if ids.empty?

    profiles = Spree::UserProfile.where(user_id: ids, hidden_at: nil).index_by(&:user_id)
    unnamed = ids.reject { |id| profiles[id]&.name.present? }
    names = if unnamed.empty?
              {}
            else
              Spree::CreatorApplication.where(user_id: unnamed, status: 'approved').order(:reviewed_at, :id)
                                       .pluck(:user_id, :display_name).to_h
            end
    ids.index_with do |id|
      profile = profiles[id]
      { handle: profile&.handle, name: profile&.name.presence || names[id] }
    end
  end

  # The kind of the product's live digital asset (its highest published version), or nil. Reads
  # the preloaded variants_including_master.digital_assets when a listing preloaded them.
  def self.digital_kind(product)
    variants = product.variants_including_master
    if variants.loaded? && variants.all? { |variant| variant.association(:digital_assets).loaded? }
      live = variants.flat_map(&:digital_assets).select(&:published?)
                     .max_by { |asset| [asset.version.to_i, asset.id.to_i] }
      return live&.kind
    end

    Spree::DigitalAsset.published.where(variant_id: variants.map(&:id)).order(version: :desc, id: :desc).pick(:kind)
  end

  # The lowest price a creator may set in the currency (Creators.config.min_price).
  def self.min_price(currency)
    setting = config.min_price
    value = if setting.is_a?(Hash)
              setting = setting.stringify_keys
              setting[currency.to_s] || setting['default']
            else
              setting
            end
    BigDecimal((value || 0).to_s)
  end

  # An order number reduced to its last four characters: creators never see who bought.
  def self.mask_order_number(number)
    number = number.to_s
    "****#{number[-4..] || number}"
  end
end
