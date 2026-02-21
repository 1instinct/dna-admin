#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /dna/tmp/pids/server.pid

echo RAILS_ENV=$RAILS_ENV

# Precompile assets if not already done (Spree needs DB so can't do this at build time)
if [ ! -d /dna/public/assets/spree ]; then
  echo "Precompiling assets (first boot, this takes a few minutes on ARM)..."
  bundle exec rake assets:precompile 2>&1
  echo "Asset precompilation complete."
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
