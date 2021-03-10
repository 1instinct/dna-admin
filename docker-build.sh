#!/bin/sh

set -e

# to blank the database ahead of time, run
#  sudo rm -rf tmp/db

docker-compose build
docker-compose up -d

docker-compose exec web rails db:create db:schema:load db:migrate db:seed

docker-compose exec web rails spree_sample:load
docker-compose restart

# follow logs...
docker-compose logs -f
