# https://docs.docker.com/compose/rails/#define-the-project
FROM ruby:2.7.2
# The qq is for silent output in the console
RUN apt-get update -qq && apt-get install -y postgresql-client nodejs

# This is given by the Ruby Image.
# This will be the de-facto directory that
# all the contents are going to be stored.
WORKDIR /dna

# We are copying the Gemfile first, so we can install
# all the dependencies without any issues
# Rils will be installed once you load it from the Gemfile
# This will also ensure that gems are cached and only updated when
# they change.
COPY Gemfile ./
COPY Gemfile.lock ./

# Note that dotenv is NOT used in production.  Environment
# comes from the deployment.
COPY .env.example .env.development

# Install the Gems
RUN gem install bundler:2.2.11 && bundle install

# We copy all the application files from the current directory to out
# /dna directory
COPY ./app /dna/app
COPY ./bin /dna/bin
COPY ./config /dna/config
COPY ./config.ru /dna/
COPY ./db /dna/db
COPY ./docs /dna/docs
COPY ./lib /dna/lib
COPY ./public /dna/public
COPY ./Rakefile /dna/
COPY ./vendor /dna/vendor

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

# Start the main process.
CMD ["rails", "server", "-b", "0.0.0.0"]
