module SpreeNavigator
  class Engine < ::Rails::Engine
    require 'spree/core'
    require 'simple-navigation'

    isolate_namespace Spree
    engine_name 'spree_navigator'

    SimpleNavigation.config_file_paths <<
      File.expand_path('../../../config', __FILE__)

    config.autoload_paths += Dir["#{config.root}/lib"]
    config.generators { |gen| gen.test_framework :rspec }

    def self.activate
      Dir[File.join(__dir__, '../../app/**/*_decorator*.rb')].each do |klass|
        Rails.application.config.cache_classes ? require(klass) : load(klass)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
