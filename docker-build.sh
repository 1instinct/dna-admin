#!/bin/sh

set -e

# to blank the database ahead of time, run
#  sudo rm -rf tmp/db

docker-compose build
docker-compose up -d

docker-compose exec web rails db:create db:schema:load db:migrate
docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed

docker-compose exec web rails spree_sample:load
docker-compose restart web

# to follow logs...
#   docker-compose logs -f
