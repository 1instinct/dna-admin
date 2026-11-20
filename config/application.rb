require_relative 'boot'

require 'rails/all'

# ostruct is stdlib but not autoloaded. The homepage_sections composed-settings fieldsets build an
# OpenStruct for fields_for, so require it explicitly rather than relying on some other gem having
# done so (a gem set that does not will fail with "uninitialized constant OpenStruct"). Ruby 3.4
# also moves ostruct to a bundled gem, where it is no longer available without being required.
require 'ostruct'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DnaAdmin
  class Application < Rails::Application
    config.to_prepare do
      # Load application's model / class decorators
      Dir.glob(File.join(File.dirname(__FILE__), "../app/**/*_decorator*.rb")) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end

      # Load application's view overrides
      Dir.glob(File.join(File.dirname(__FILE__), "../app/overrides/*.rb")) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.2
  end
end
