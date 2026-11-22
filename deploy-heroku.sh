#!/bin/bash
set -e

# Heroku Deployment Script for Beeper Admin
# Usage: ./deploy-heroku.sh <app-name>

APP_NAME=$1

if [ -z "$APP_NAME" ]; then
  echo "Error: Please provide an app name"
  echo "Usage: ./deploy-heroku.sh <app-name>"
  exit 1
fi

echo "🚀 Deploying to Heroku app: $APP_NAME"
echo ""

# Check if app exists
if ! heroku apps:info -a $APP_NAME &> /dev/null; then
  echo "❌ App '$APP_NAME' not found. Please create it first:"
  echo "   heroku create $APP_NAME"
  exit 1
fi

echo "✓ App found"

# Set up git remote
echo "🔗 Configuring git remote..."
git remote remove heroku 2>/dev/null || true
heroku git:remote -a $APP_NAME
echo "✓ Git remote configured"
echo ""

# Set stack to container
echo "📦 Setting stack to container..."
heroku stack:set container -a $APP_NAME

# Push container
echo "🔨 Building and pushing container..."
git push heroku main:main || git push heroku master:master

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Set environment variables (see HEROKU_DEPLOYMENT.md)"
echo "2. Run: heroku run rails db:seed -a $APP_NAME"
echo "3. (Optional) Run: heroku run rails spree_sample:load -a $APP_NAME"
echo ""
echo "View your app:"
echo "heroku open -a $APP_NAME"
