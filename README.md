# DOCKER SETUP

## Build
This should only have to be done once, or whenever the Gemfile is updated.
```
docker-compose build
```

## Create Containers

```
docker-compose up
```

DNA Admin should now be available at localhost:8080,
but it probably needs to be set up first.

## Set up system

In a new terminal run:

```
docker-compose exec web rails db:create db:schema:load db:migrate &&
docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed &&
docker-compose exec web rails spree_sample:load &&
docker-compose restart
```

OPTIONAL: Create a new admin user.  This can be used to reset the
admin user also:

```
docker-compose exec web rails spree_auth:admin:create
```

default is:

email: spree@example.com

password: spree123

## Reset DB

This will reset the existing database back to blank.

```
docker-compose exec web rails db:reset railties:install:migrations db:migrate db:seed spree_sample:load
```

You could also blow away all the DB files.  WARNING! You'll have to start
the install over again if you do this.

```
sudo rm -rf tmp/db
```

## Extensions

The system uses 3 spree extensions

* `spree_static_content`
  [github](https://github.com/spree-contrib/spree_static_content)
* `spree_digital`
  [github](https://github.com/spree-contrib/spree_digital)
* `spree_promo_users_codes`
  [github](https://github.com/vinsol-spree-contrib/spree_promo_users_codes)

Each one is installed _after_ spree, with it's own migrations generated using a
specific `bundle exec rails g` command, which can be found on the README of the github
page for each project.  This only needs to be done once after spree is installed or upgraded.

## TODO

Other things we may need to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions
