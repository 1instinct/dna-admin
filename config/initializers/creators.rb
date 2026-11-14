# Creators (app/services/creators.rb holds Creators.config).
#
# ENV:
#   CREATORS_MARKETPLACE_TAXON  permalink of the taxon approved creator products join (default "marketplace")
#
# Defaults: creators keep 70% of a sale (default_share_bps 7000); earnings become payable 14 days
# after the order completes (hold_days). Run `rake marketplace:sweep` daily from a scheduler; the
# creator and admin pages also sweep when they are read.
#
#   Rails.application.config.to_prepare do
#     Creators.configure { |c| c.default_share_bps = 8000 }
#   end
Rails.application.config.to_prepare do
  Creators.configure do |c|
    c.default_share_bps = 7000
    c.hold_days = 14
    c.marketplace_taxon_permalink = ENV.fetch('CREATORS_MARKETPLACE_TAXON', 'marketplace')
  end

  # Library items and storefront products name their creator.
  DigitalAssets.configure do |c|
    c.creator_for = ->(product) { Creators.identity(product) }
  end
end
