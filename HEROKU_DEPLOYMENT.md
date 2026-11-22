# Heroku Deployment Guide

This guide will help you deploy Beeper Admin to Heroku using Docker containers with the smallest Postgres instance.

## Prerequisites

1. [Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli) installed
2. Git repository initialized
3. Docker installed (for local testing)

## Quick Start

### 1. Create Heroku App

```bash
# Create a new app
heroku create your-app-name

# Or connect to an existing app:
heroku git:remote -a your-app-name
```

### 2. Add Postgres Database

The app uses `heroku-postgresql:essential-0` ($5/month - smallest paid plan):

```bash
# This is automatically provisioned via heroku.yml
# Or manually add:
heroku addons:create heroku-postgresql:essential-0 -a your-app-name
```

**Note:** The free `hobby-dev` plan is no longer available. The `essential-0` plan ($5/mo) provides:
- 10,000 rows
- 1GB storage
- 20 connections

### 3. Set Environment Variables

**Required Variables:**

```bash
# App name for the app (replace YOUR_APP_NAME)
APP_NAME=your-app-name

# Generate secret keys
heroku config:set SECRET_KEY_BASE=$(openssl rand -hex 64) -a $APP_NAME
heroku config:set DEVISE_SECRET_KEY=$(openssl rand -hex 64) -a $APP_NAME
heroku config:set TOKEN_KEY_BASE=$(openssl rand -hex 64) -a $APP_NAME

# Rails environment
heroku config:set RAILS_ENV=production -a $APP_NAME
heroku config:set RACK_ENV=production -a $APP_NAME
heroku config:set RAILS_LOG_TO_STDOUT=true -a $APP_NAME
heroku config:set RAILS_SERVE_STATIC_FILES=true -a $APP_NAME

# Branding
heroku config:set COMPANY_LOGO=/assets/beeper_logo.png -a $APP_NAME
heroku config:set LOGIN_BACKGROUND=/assets/beeper-login-background.jpg -a $APP_NAME
heroku config:set COMPANY_BACKGROUND=/assets/beeper-login-background.jpg -a $APP_NAME

# Site configuration
heroku config:set SITE_TITLE="Beeper Admin" -a $APP_NAME
heroku config:set SITE_ADMIN_NAME="Admin" -a $APP_NAME
```

**AWS S3 Configuration (Required for file uploads):**

```bash
heroku config:set AWS_ACCESS_KEY_ID=your_access_key -a $APP_NAME
heroku config:set AWS_SECRET_ACCESS_KEY=your_secret_key -a $APP_NAME
heroku config:set AWS_REGION_NAME=us-west-1 -a $APP_NAME
heroku config:set AWS_REGION=us-west-1 -a $APP_NAME
heroku config:set AWS_BUCKET_NAME=your-bucket-name -a $APP_NAME
heroku config:set AWS_BUCKET=your-bucket-name -a $APP_NAME
```

**Mailgun Configuration (for emails):**

```bash
heroku config:set MAILGUN_HOST=smtp.mailgun.org -a $APP_NAME
heroku config:set MAILGUN_USER=postmaster@your-domain.com -a $APP_NAME
heroku config:set MAILGUN_PASS=your_mailgun_password -a $APP_NAME
heroku config:set MAILGUN_PORT=587 -a $APP_NAME
heroku config:set MAILGUN_DOMAIN=your-domain.com -a $APP_NAME
```

**Optional - DNA API Integration:**

```bash
heroku config:set DNA_API_URL=your-api-url -a $APP_NAME
heroku config:set DNA_API_KEY=your-api-key -a $APP_NAME
heroku config:set SITE_URL=your-site-url -a $APP_NAME
heroku config:set SITE_SLUG=your-site-slug -a $APP_NAME
```

**Optional - Twilio (SMS):**

```bash
heroku config:set TWILIO_ACCOUNT_SID=your_sid -a $APP_NAME
heroku config:set TWILIO_AUTH_TOKEN=your_token -a $APP_NAME
heroku config:set TWILIO_PHONE_NUMBER=your_phone_number -a $APP_NAME
```

**Optional - Pusher (Real-time features):**

```bash
heroku config:set PUSHER_APP_ID=your_app_id -a $APP_NAME
heroku config:set PUSHER_KEY=your_key -a $APP_NAME
heroku config:set PUSHER_SECRET=your_secret -a $APP_NAME
heroku config:set PUSHER_CLUSTER=us3 -a $APP_NAME
```

### 4. Set Environment Variables from File (Alternative)

If you have all your variables in a file:

```bash
# Copy and edit the template
cp .env.development .env.production

# Edit .env.production with your production values
# Then upload to Heroku:
cat .env.production | grep -v '^#' | grep -v '^$' | while IFS='=' read -r key value; do
  heroku config:set "$key=$value" -a $APP_NAME
done
```

### 5. Deploy to Heroku

```bash
# Connect to your existing app (if not already connected)
heroku git:remote -a your-app-name

# Example for beeper-admin-prod:
# heroku git:remote -a beeper-admin-prod

# Make sure you're on the correct branch
git checkout main  # or master

# Set stack to container (uses heroku.yml)
heroku stack:set container -a your-app-name

# Deploy
git push heroku main:main
# Or if using master branch:
# git push heroku master:master
```

The `heroku.yml` configuration will:
- Build the Docker container
- Run database migrations automatically (release phase)
- Start the Puma web server

### 6. Initialize Database

After deployment, seed the database:

```bash
# Create admin user and seed base data
heroku run rails db:seed -a $APP_NAME

# When prompted, enter admin credentials
# Default: spree@example.com / spree123

# Optional: Load sample products/data
heroku run rails spree_sample:load -a $APP_NAME

# Optional: Generate affiliate codes
heroku run rails reffiliate:generate -a $APP_NAME
```

### 7. Create Admin User (Alternative Method)

If db:seed doesn't prompt for credentials:

```bash
heroku run rails spree_auth:admin:create -a $APP_NAME
```

### 8. Open Your App

```bash
heroku open -a $APP_NAME
```

Your admin panel will be at: `https://your-app-name.herokuapp.com/admin`

## Useful Commands

### View Logs

```bash
heroku logs --tail -a $APP_NAME
```

### Run Rails Console

```bash
heroku run rails console -a $APP_NAME
```

### Run Database Migrations

```bash
heroku run rails db:migrate -a $APP_NAME
```

### Check Database Status

```bash
heroku pg:info -a $APP_NAME
```

### Reset Database (⚠️ Destroys all data)

```bash
heroku pg:reset DATABASE -a $APP_NAME --confirm $APP_NAME
heroku run rails db:schema:load -a $APP_NAME
heroku run rails db:seed -a $APP_NAME
```

### Scale Dynos

```bash
# Check current dyno usage
heroku ps -a $APP_NAME

# Scale web dynos (default is 1)
heroku ps:scale web=1 -a $APP_NAME
```

### Restart App

```bash
heroku restart -a $APP_NAME
```

## Troubleshooting

### "No default language could be detected" error

Set the buildpack explicitly:
```bash
heroku buildpacks:clear -a $APP_NAME
heroku stack:set container -a $APP_NAME
```

### Database connection errors

Check that DATABASE_URL is set:
```bash
heroku config:get DATABASE_URL -a $APP_NAME
```

### Asset issues

Ensure `RAILS_SERVE_STATIC_FILES=true` is set:
```bash
heroku config:set RAILS_SERVE_STATIC_FILES=true -a $APP_NAME
```

### Migration errors

If migrations fail during deployment, run them manually:
```bash
heroku run rails db:migrate -a $APP_NAME
heroku restart -a $APP_NAME
```

### Check app is running

```bash
heroku ps -a $APP_NAME
heroku logs --tail -a $APP_NAME
```

## Cost Breakdown

**Minimum monthly cost: ~$10/month**

- Eco Dyno (web): $5/month (512MB RAM)
- Postgres Essential-0: $5/month
- AWS S3: ~$1-2/month (estimated for storage/bandwidth)

**Recommended for production: ~$29/month**

- Basic Dyno (web): $7/month (512MB RAM, no sleeping)
- Postgres Essential-1: $9/month (more connections/storage)
- AWS S3: ~$2-5/month
- Optional: Heroku Data Clips for backups

## Updating the App

```bash
# Make your changes, commit them
git add .
git commit -m "Your changes"

# Push to Heroku
git push heroku main:main
```

Migrations will run automatically during the release phase.

## Backup and Restore

### Create Backup

```bash
heroku pg:backups:capture -a $APP_NAME
heroku pg:backups:download -a $APP_NAME
```

### Restore from Backup

```bash
heroku pg:backups:restore <backup-url> DATABASE_URL -a $APP_NAME
```

## Security Checklist

- ✅ All secret keys generated with secure random strings
- ✅ AWS credentials stored as environment variables
- ✅ Database runs on private network
- ✅ HTTPS enforced (automatic with Heroku)
- ✅ CORS configured (check config/initializers/cors.rb for production)
- ✅ No .env files committed to Git

## Additional Resources

- [Heroku Container Registry](https://devcenter.heroku.com/articles/container-registry-and-runtime)
- [Heroku Postgres Plans](https://www.heroku.com/postgres-pricing)
- [Rails on Heroku](https://devcenter.heroku.com/articles/getting-started-with-rails7)
