#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /myapp/tmp/pids/server.pid

echo RAILS_ENV=$RAILS_ENV

if [ ! -e assets_precompiled ] ; then
    rails assets:precompile
    touch assets_precompiled
    exit 0
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
