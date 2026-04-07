# Puma configuration for production (Azure Container Apps)
# https://puma.io/puma/Puma/DSL.html

# Thread pool — Container Apps allocates 0.5 CPU per container
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
min_threads_count = ENV.fetch("RAILS_MIN_THREADS", max_threads_count).to_i
threads min_threads_count, max_threads_count

# Workers — for Container Apps with 0.5 CPU, use 2 workers
# WEB_CONCURRENCY=0 disables workers (single mode, useful for debugging)
workers ENV.fetch("WEB_CONCURRENCY", 2).to_i

# Preload app for Copy-on-Write memory savings with workers
preload_app!

# Port
port ENV.fetch("PORT", 3000)

# Environment
environment ENV.fetch("RAILS_ENV", "development")

# Worker boot hook — re-establish DB connections in forked workers
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `bin/rails restart`
plugin :tmp_restart

# Logging
if ENV["RAILS_LOG_TO_STDOUT"] == "true"
  stdout_redirect "/dev/stdout", "/dev/stderr", true
end
