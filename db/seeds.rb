# Load Spree core defaults (countries, states, zones, roles, etc.)
Spree::Core::Engine.load_seed if defined?(Spree::Core)
Spree::Auth::Engine.load_seed if defined?(Spree::Auth)

# Load Cntrl+ specific data
load Rails.root.join("db/seeds/cntrlplus.rb")
