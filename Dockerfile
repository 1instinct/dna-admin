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
COPY .env.example .env.development
# Installs the Gem File.
RUN gem install bundler:2.0.2 && bundle install

# Install the Gems
RUN gem install bundler:2.2.11 && bundle install

# We copy all the application files from the current directory to out
# /dna directory
COPY app /dna/
COPY bin /dna/
COPY config /dna/
COPY config.ru /dna/
COPY db /dna/
COPY docs /dna/
COPY lib /dna/
COPY public /dna/
COPY Rakefile /dna/
COPY vendor /dna/

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

# Start the main process.
CMD ["rails", "server", "-b", "0.0.0.0"]
