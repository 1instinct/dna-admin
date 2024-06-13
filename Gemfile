source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.1.3'
# Use postgresql as the database for Active Record
gem 'pg'
# Use Puma as the app server
gem 'puma', '~> 4.3'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.0'
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
<<<<<<< HEAD
<<<<<<< HEAD
=======
gem 'rack-cors'
>>>>>>> 5fdf3ea (Add cors initializer)
=======
>>>>>>> 5800bef (regenerated lockfiles with bundler 2.0.2)
# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Handle CORs request errors
gem 'rack-cors', :require => 'rack/cors'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '~> 1.8.1'

gem "aws-sdk-s3", require: false

<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
gem 'spree', github: '1instinct/spree'
gem 'spree_auth_devise', '~> 4.3'
gem 'spree_gateway', '~> 3.9'
=======
gem 'spree', '~> 3.7'
=======
gem 'spree', '~> 3.7.0'
>>>>>>> 739777e (bump spree version to try to solve https://github.com/spree/spree/issues/8616)
=======
gem 'spree', '~> 3.7.3'
>>>>>>> dbc674d (bump spree version again, this time to 3.7.3 explicitly)
=======
gem 'spree', '~> 3.7'
>>>>>>> db57f19 (rename store_controller >> store_controller_decorator)
gem 'spree_auth_devise', '~> 3.5'
gem 'spree_gateway', '~> 3.4'
>>>>>>> 48588a8 (downgrade spree_auth_devise)
gem 'spree_static_content', github: 'spree-contrib/spree_static_content'
<<<<<<< HEAD
<<<<<<< HEAD
=======
gem 'spree', '~> 4.2.0.rc4'
=======
gem 'spree', path: './external/spree'
>>>>>>> bbbebba (FIXME: hacking things to try and get the heroku deploy to work)
=======
gem 'spree', github: 'ddombrowsky/spree', branch: 'instinct-dna'
>>>>>>> 29529b7 (added ddombrowsky/spree fork of spree)
=======
gem 'spree', github: '1instinct/spree', branch: 'instinct-dna'
>>>>>>> faf293b (Updated spree fork to 1instinct)
gem 'spree_auth_devise', '~> 4.3'
gem 'spree_gateway', '~> 3.9'
gem 'spree_static_content', github: 'spree-contrib/spree_static_content'
>>>>>>> 9eb368b (set Gemfile to use spree 4.2)
gem 'spree_digital', github: 'spree-contrib/spree_digital'
<<<<<<< HEAD
gem 'spree_reffiliate', github: 'Gaurav2728/spree_reffiliate'
gem 'spree_loyalty_points', github: 'Gaurav2728/spree-loyalty-points'

# doesn't support spree 4
#gem 'spree_promo_users_codes', github: 'vinsol-spree-contrib/spree_promo_users_codes', branch: 'master'

# doesn't support spree 4
#gem 'spree_promo_users_codes', github: 'vinsol-spree-contrib/spree_promo_users_codes', branch: 'master'

gem 'sprockets-helpers', '~> 1.2.1'

gem 'rest-client'
# Tool to create APi and it's documentation
gem 'swagger-blocks'
<<<<<<< HEAD
=======
gem 'spree_promo_users_codes', github: 'vinsol-spree-contrib/spree_promo_users_codes', branch: 'master'
<<<<<<< HEAD
>>>>>>> 3f5a283 (add Messages to schema (again?), add vinsol spree-promo-users-codes)
=======
gem 'spree_digital', github: 'spree-contrib/spree_digital'
>>>>>>> f36d818 (handle CORs (add pkg), add digital downloadable products, refactor app overrides, update schema version, add migrations)
=======
gem 'vinsol_spree_themes', github: 'vinsol-spree-contrib/spree_themes', branch: 'master'
gem 'import_products', :git => 'git://github.com/joshmcarthur/spree-import-products.git'
=======
>>>>>>> b15e5aa (Dockerize dna admin)

gem 'sprockets-helpers', '~> 1.2.1'
>>>>>>> d640f63 (add in some new vendor code, tweak example envs, fux w db stuff)

gem 'rest-client'
=======
>>>>>>> 49fceaf (Add swagger gem for the APi's)

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'dotenv-rails'
  gem 'prettier'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  # use to seed the records
  gem "factory_bot_rails"
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
  gem 'selenium-webdriver'
  # Easy installation and use of chromedriver to run system tests with Chrome
  gem 'chromedriver-helper'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
