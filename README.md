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
docker-compose exec web rails db:create db:migrate db:schema:load &&
docker-compose exec web rails db:seed &&
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
