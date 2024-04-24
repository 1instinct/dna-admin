module Spree
  # These will be saved with key: spree/app_configuration/hot_salsa
  AppConfiguration.class_eval do
    preference :hot_salsa, :boolean, :default => true
    preference :dark_chocolate, :boolean, default: true
    preference :color, :string, :default => '#008EAE'
    preference :favorite_number, :integer, :default => 42
    preference :language, :string, default: 'English'
  end

  # Config is an instance of AppConfiguration
  # Config.hot_salsa = false
end
