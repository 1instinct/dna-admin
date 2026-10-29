ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'

# Tests never reach real third-party services (App Store, Google Play, ...).
WebMock.disable_net_connect!(allow_localhost: true)

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

class ActiveSupport::TestCase
    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include FactoryBot::Syntax::Methods

    # Add more helper methods to be used by all tests here...
end
