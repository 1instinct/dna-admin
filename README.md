# DOCKER SETUP
This repo is using Spree 4.2.4
## Build

This should only have to be done once, or whenever the Gemfile is updated.

```docker-compose build
```

## Create Containers

```docker-compose up
```

DNA Admin should now be available at localhost:8080,
but it probably needs to be set up first.

## Set up system

In a new terminal run:

```docker-compose exec web rails db:create db:schema:load db:migrate &&
docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed &&
docker-compose exec web rails spree_sample:load &&
docker-compose restart
```

### The Default User

email: spree@example.com
password: spree123

## Reset DB

This will reset the existing database back to blank.

```docker-compose exec web rails db:reset railties:install:migrations db:migrate db:seed spree_sample:load
```

You could also blow away all the DB files.  WARNING! You'll have to start
the install over again if you do this.

```sudo rm -rf tmp/db
```
## Rails Console
`docker exec -it dna-admin_web_1 bin/rails console`
## Extensions

The system uses 3 spree extensions

* `spree_reffiliate` (Thanks @Gaurav2728)
  [github](https://github.com/Gaurav2728/spree_reffiliate)
<<<<<<< HEAD
* `spree_loyalty_points` (Thanks @Gaurav2728)
  [github](https://github.com/Gaurav2728/spree_loyalty_points)
=======
>>>>>>> master
* `spree_static_content`
  [github](https://github.com/spree-contrib/spree_static_content)
* `spree_digital`
  [github](https://github.com/spree-contrib/spree_digital)
* `spree_promo_users_codes`
  [github](https://github.com/vinsol-spree-contrib/spree_promo_users_codes)

Each one is installed _after_ spree, with it's own migrations generated using a
specific `bundle exec rails g` command, which can be found on the README of the github
page for each project.  This only needs to be done once after spree is installed or upgraded.

<<<<<<< HEAD
## CLI Scripts

`./tools/docker-scripts.sh reload_db`

## Swagger UI

=======
>>>>>>> master
## Scripts

1. Generate **Affiliate Codes** for Existing Users: `bundle exec rake reffiliate:generate`
1. Create or reset a **New Admin User**: `docker-compose exec web rails spree_auth:admin:create`
<<<<<<< HEAD
1. Load Spree sample data & seed data: `rake db:seed && rails spree_sample:load`
=======
>>>>>>> master

## Deploy

This uses heroku ruby buildpack on the heroku-20 stack.  The `master` branch
on github is hooked in to the deployment.

<<<<<<< HEAD
Git: <https://github.com/POL-Clothing/pol-admin>
=======
Git: https://github.com/POL-Clothing/pol-admin
>>>>>>> master

### Testing Production Settings

To test the production settings locally (used to test things like the S3 buckets
for active storage), you need to set environment variables directly in
the `docker-compose.yml` file.  The production environment is configured
to NOT use `.env` files.

To do this, apply the following patch to `docker-compose.yml` (after filling
in real values for the keys and bucket name):

```--- docker-compose.yml.orig     2021-06-02 10:50:59.011383071 -0400
+++ docker-compose.yml  2021-06-02 10:51:03.267414021 -0400
@@ -16,4 +16,10 @@
     depends_on:
       - db
     environment:
-      DATABASE_URL: postgres://postgres:password@db:5432/dna_admin_development
+      DATABASE_URL: postgres://postgres:password@db:5432/dna_admin_production
+      RAILS_ENV: production
+      AWS_REGION_NAME: us-west-1
+      AWS_BUCKET_NAME:
+      AWS_ACCESS_KEY_ID:
+      AWS_SECRET_ACCESS_KEY:
+      RAILS_SERVE_STATIC_FILES: 1
```

After building and starting the container, you will need to build the assets
in the local container with:

```docker-compose exec web rails assets:precompile
docker-compose restart
```

## Keeping Your Code Updated

When there are lots of active changes occuring on this repo, make sure to regularly:

1. Commit (or stash) your local changes on your branch
1. `git fetch origin`
1. `git checkout main`
1. `git pull origin main`
1. `git checkout <your_branch>`
1. `git merge main`
1. Fix merge conflicts (if any)
1. `git add .`
1. `git commit -m 'merge in latest main'`

Done!
…now you will be up-to-date with latest code. Do this before you submit your PR, and you can be sure it will be a clean merge.

http://localhost:8080/apidocs/swagger_ui
Make sure to change the port that the UI is expecting in the search bar

## TODO

Other things we may need to cover:

1. Ruby version

1. System dependencies

1. Configuration

1. Database creation

1. Database initialization

1. How to run the test suite

1. Services (job queues, cache servers, search engines, etc.)

1. Deployment instructions
