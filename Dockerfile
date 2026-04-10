# https://docs.docker.com/compose/rails/#define-the-project
FROM ruby:3.2.2
# The qq is for silent output in the console
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    curl \
    && rm -rf /var/lib/apt/lists/*

# This is given by the Ruby Image.
# This will be the de-facto directory that
# all the contents are going to be stored.
WORKDIR /dna

# We are copying the Gemfile first, so we can install
# all the dependencies without any issues
# Rils will be installed once you load it from the Gemfile
# This will also ensure that gems are cached and only updated when
# they change.
COPY Gemfile Gemfile.lock* ./

# Note that dotenv is NOT used in production.  Environment
# comes from the deployment.
COPY .env.development .env.development

# Install the Gems
RUN gem install bundler:2.4.22

RUN bundle config set force_ruby_platform true

RUN bundle install

COPY . ./

# Precompile assets
# RUN RAILS_ENV=production bundle exec rake assets:precompile

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

# Start the main process.
CMD ["rails", "server", "-b", "0.0.0.0"]
