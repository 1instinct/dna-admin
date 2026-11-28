source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.1.3'
# Use postgresql as the database for Active Record
gem 'pg', '~> 1.5.0'
gem "ffi", "< 1.17.0"
# Use Puma as the app server
gem 'puma', '~> 4.3'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.0'
# Sass engine required by bootstrap
gem 'sassc-rails'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'mini_racer', platforms: :ruby

# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 4.2'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'
gem 'rack-cors'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'
gem 'image_processing', '~> 1.2'
# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '~> 1.8.1'

gem "aws-sdk-s3", '~> 1.96'

gem "net-http"

gem 'spree', github: '1instinct/spree', branch: 'instinct-4.2.5'
gem 'spree_auth_devise', '~> 4.3'
gem 'spree_gateway', '~> 3.9'

gem 'spree_static_content', github: 'spree-contrib/spree_static_content'

# gem 'spree_digital', github: 'spree-contrib/spree_digital'
gem 'spree_reffiliate', github: '1instinct/spree_reffiliate'
gem 'spree_loyalty_points', github: '1instinct/spree-loyalty-points'
# gem 'spree_avatax_official', github: 'spree-contrib/spree_avatax_official', branch: 'spree-4-1-plus'
# gem 'spree_avatax_official', '~> 1.9.0'

gem 'spree_avatar', github: '1instinct/spree_avatar'
gem 'spree_editor', github: 'spree-contrib/spree_editor'
# Companion gem for the Spree Admin Native mobile admin app (and its forks): QR device
# pairing, new-order push notifications, the Home summary, tree views, the inbox, carts and
# visitors (0.7.0). Pinned to a commit; see
# https://github.com/1instinct/spree-admin-native/tree/520fe6a57b429cc8cc611bf079046fe717518b45/gems/spree_admin_native
gem 'spree_admin_native', github: '1instinct/spree-admin-native', ref: '520fe6a57b429cc8cc611bf079046fe717518b45',
                          glob: 'gems/spree_admin_native/*.gemspec'

gem 'paperclip', '~> 6.1.0'

# doesn't support spree 4
#gem 'spree_promo_users_codes', github: 'vinsol-spree-contrib/spree_promo_users_codes', branch: 'master'

gem 'sprockets-helpers', '~> 1.2.1'

gem 'rest-client'

# In-app purchase verification (StoreKit 2 JWS, App Store Server API, Google Play service-account tokens)
gem 'jwt', '~> 2.7'
# Tool to create APi and it's documentation
gem 'swagger-blocks'

# Error and performance reporting; off until SENTRY_DSN is set (config/initializers/sentry.rb).
# Unpinned on purpose so bundler picks a release that supports Ruby 2.7.2; newer sentry-ruby
# releases need Ruby 3.
gem 'sentry-ruby'
gem 'sentry-rails'
# gem 'spree_promo_users_codes', github: 'vinsol-spree-contrib/spree_promo_users_codes', branch: 'master'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'dotenv-rails'
  gem 'prettier'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  # use to seed the records
  gem 'factory_bot_rails', '~> 5.2'
  # Use to generate fake data
  gem 'faker'
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'matrix'
  # Pinned to 3.x: chromedriver-helper 2.1.1 calls
  # Selenium::WebDriver::Chrome.driver_path= at load, which Selenium 4 removed,
  # so an unpinned resolve to 4.x aborts `rails test` at boot.
  gem 'selenium-webdriver', '~> 3.142'
  # Easy installation and use of chromedriver to run system tests with Chrome
  gem 'chromedriver-helper'
  # Stub all outbound HTTP in tests (store APIs are never called for real)
  gem 'webmock', '~> 3.18'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
