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

# Install the Gems
RUN gem install bundler:2.2.11 && bundle install

# We copy all the files from the current directory to out
# /app directory
# Pay close attention to the dot (.)
# The first one will select ALL the files of the current directory,
# The second dot will copy it to the WORKDIR!
COPY . /dna

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

# Start the main process.
CMD ["rails", "server", "-b", "0.0.0.0"]
