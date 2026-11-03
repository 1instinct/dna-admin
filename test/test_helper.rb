ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

# config/initializers/active_storage.rb points every environment at S3; tests use local disk.
ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(:test)

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

class ActiveSupport::TestCase
    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include FactoryBot::Syntax::Methods

    # Add more helper methods to be used by all tests here...
end
