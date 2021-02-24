#!/bin/sh

set -e

docker-compose build
docker-compose up -d
docker-compose exec web rails db:create db:migrate db:schema:load
docker-compose exec web rails db:seed
docker-compose exec web rails spree_sample:load
docker-compose restart

# follow logs...
docker-compose logs -f
