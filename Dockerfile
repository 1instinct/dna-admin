FROM ruby:2.7.2

RUN apt-get update -qq && apt-get install -y \
    postgresql-client \
    nodejs \
    curl

# Install Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt-get update -qq && apt-get install -y yarn

WORKDIR /dna

COPY Gemfile Gemfile.lock ./
RUN gem install bundler:2.2.11 && bundle install

COPY . ./

# Precompile assets using the database service
RUN RAILS_ENV=production DATABASE_URL=postgresql://postgres:c03213be9ab9014e@10.152.183.57:5432/dna_admin_production bundle exec rake assets:precompile

COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]

