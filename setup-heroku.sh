#!/bin/bash
# Quick Heroku Setup for Beeper Admin
# This script helps you set up a new Heroku deployment interactively

set -e

echo "🎯 Beeper Admin - Heroku Setup Wizard"
echo "======================================"
echo ""

# Get app name
read -p "Enter your Heroku app name: " APP_NAME

if [ -z "$APP_NAME" ]; then
  echo "❌ App name is required"
  exit 1
fi

echo ""
echo "Setting up Heroku app: $APP_NAME"
echo ""

# Check if Heroku CLI is installed
if ! command -v heroku &> /dev/null; then
    echo "❌ Heroku CLI not found. Please install it first:"
    echo "   https://devcenter.heroku.com/articles/heroku-cli"
    exit 1
fi

# Check if app exists and create or connect
echo "1️⃣  Checking Heroku app..."
if heroku apps:info -a $APP_NAME &> /dev/null; then
  echo "   ✓ App exists: $APP_NAME"
  echo "   🔗 Adding git remote..."
  
  # Remove existing heroku remote if it exists
  git remote remove heroku 2>/dev/null || true
  
  # Add the remote
  heroku git:remote -a $APP_NAME
  echo "   ✓ Git remote configured"
else
  echo "   📦 App doesn't exist, creating..."
  heroku create $APP_NAME
  echo "   ✓ App created and git remote configured"
fi

# Add Postgres
echo ""
echo "2️⃣  Adding PostgreSQL database (essential-0 plan - $5/month)..."
if heroku addons:info heroku-postgresql -a $APP_NAME &> /dev/null; then
  echo "   ✓ Postgres already added"
else
  heroku addons:create heroku-postgresql:essential-0 -a $APP_NAME
  echo "   ✓ Postgres added"
fi

# Set stack
echo ""
echo "3️⃣  Setting stack to container..."
heroku stack:set container -a $APP_NAME
echo "   ✓ Stack set"

# Generate secrets
echo ""
echo "4️⃣  Generating secret keys..."
SECRET_KEY_BASE=$(openssl rand -hex 64)
DEVISE_SECRET_KEY=$(openssl rand -hex 64)
TOKEN_KEY_BASE=$(openssl rand -hex 64)

heroku config:set \
  SECRET_KEY_BASE=$SECRET_KEY_BASE \
  DEVISE_SECRET_KEY=$DEVISE_SECRET_KEY \
  TOKEN_KEY_BASE=$TOKEN_KEY_BASE \
  RAILS_ENV=production \
  RACK_ENV=production \
  RAILS_LOG_TO_STDOUT=true \
  RAILS_SERVE_STATIC_FILES=true \
  -a $APP_NAME

echo "   ✓ Secrets configured"

# Branding
echo ""
echo "5️⃣  Setting default branding..."
heroku config:set \
  COMPANY_LOGO=/assets/beeper_logo.png \
  LOGIN_BACKGROUND=/assets/beeper-login-background.jpg \
  COMPANY_BACKGROUND=/assets/beeper-login-background.jpg \
  SITE_TITLE="Beeper Admin" \
  SITE_ADMIN_NAME="Admin" \
  -a $APP_NAME

echo "   ✓ Branding configured"

echo ""
echo "✅ Basic setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Configure AWS S3 (REQUIRED for file uploads):"
echo "   heroku config:set \\"
echo "     AWS_ACCESS_KEY_ID=your_key \\"
echo "     AWS_SECRET_ACCESS_KEY=your_secret \\"
echo "     AWS_REGION_NAME=us-west-1 \\"
echo "     AWS_REGION=us-west-1 \\"
echo "     AWS_BUCKET_NAME=your-bucket \\"
echo "     AWS_BUCKET=your-bucket \\"
echo "     -a $APP_NAME"
echo ""
echo "2. Configure Mailgun (REQUIRED for emails):"
echo "   heroku config:set \\"
echo "     MAILGUN_HOST=smtp.mailgun.org \\"
echo "     MAILGUN_USER=postmaster@your-domain.com \\"
echo "     MAILGUN_PASS=your_password \\"
echo "     MAILGUN_PORT=587 \\"
echo "     MAILGUN_DOMAIN=your-domain.com \\"
echo "     -a $APP_NAME"
echo ""
echo "3. Deploy your app:"
echo "   git push heroku main:main"
echo "   # Or use: ./deploy-heroku.sh $APP_NAME"
echo ""
echo "4. Seed the database:"
echo "   heroku run rails db:seed -a $APP_NAME"
echo ""
echo "5. Open your app:"
echo "   heroku open -a $APP_NAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 Full documentation: HEROKU_DEPLOYMENT.md"
echo ""
