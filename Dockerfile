# https://docs.docker.com/compose/rails/#define-the-project
FROM ruby:2.7.2
# Fix Debian repository URLs for old Buster image
RUN sed -i 's|http://deb.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/security.debian.org/d' /etc/apt/sources.list
# The qq is for silent output in the console
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    curl \
    && rm -rf /var/lib/apt/lists/*
    
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

RUN mkdir /beeper-admin
WORKDIR /beeper-admin

COPY Gemfile /beeper-admin/Gemfile
COPY Gemfile.lock /beeper-admin/Gemfile.lock

RUN gem install bundler -v 2.4.22 && \
    bundle config set force_ruby_platform true && \
    bundle install

COPY . /beeper-admin

EXPOSE 3000
CMD rm -f tmp/pids/server.pid && bundle exec rails server -b 0.0.0.0