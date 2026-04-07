# config/initializers/cors.rb

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development?
      origins '*'
    else
      # Use comma-separated list: ALLOWED_ORIGINS=https://dna.com,https://www.dna.com
      origins ENV['ALLOWED_ORIGINS']&.split(',') || 'https://dna-admin-staging.instinct.is'
    end
    
    resource '*', 
      headers: :any, 
      methods: [:get, :post, :patch, :put, :delete, :options, :head]
  end
end