Rails.application.config.active_storage.service = :amazon

puts "AWS_ACCESS_KEY_ID: #{ENV['AWS_ACCESS_KEY_ID']}"
puts "AWS_SECRET_ACCESS_KEY: #{ENV['AWS_SECRET_ACCESS_KEY']}"
puts "AWS_REGION_NAME: #{ENV['AWS_REGION_NAME']}"
puts "AWS_BUCKET_NAME: #{ENV['AWS_BUCKET_NAME']}"

puts "ActiveStorage configured with:"
puts "AWS Access Key: #{Rails.application.credentials.dig(:aws, :access_key_id) || ENV['AWS_ACCESS_KEY_ID']}"
puts "AWS Secret Key: #{Rails.application.credentials.dig(:aws, :secret_access_key) || ENV['AWS_SECRET_ACCESS_KEY']}"
puts "AWS Region: #{Rails.application.credentials.dig(:aws, :region) || ENV['AWS_REGION_NAME']}"
puts "AWS Bucket: #{Rails.application.credentials.dig(:aws, :bucket) || ENV['AWS_BUCKET_NAME']}"