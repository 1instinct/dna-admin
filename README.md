# DOCKER SETUP

`docker-compose up --build` (say "no" to all overwrites)

in a new terminal run:

`docker-compose run web rake db:create db:migrate db:schema:load db:seed && docker-compose run web rake spree_sample:load`

reset db

`docker-compose run web rake db:reset railties:install:migrations db:migrate db:seed spree_sample:load`

create admin user if missing or fogot

`docker-compose run web rake spree_auth:admin:create`

default is:

email: spree@example.com

password: spree123

all regular ruby commands work preceeded with:

`docker-compose run web [you command here]`

Other things we may need to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions

- ...
