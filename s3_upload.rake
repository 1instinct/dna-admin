require 'aws-sdk-s3'

namespace :s3 do
  desc "Upload images to S3 bucket"
  task upload_images: :environment do
    images_path = ENV['IMAGES_PATH'] || Rails.root.join('db', 'seed_data', 'images')
    bucket_name = ENV['AWS_BUCKET_NAME']
    
    s3 = Aws::S3::Client.new(
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      region: ENV['AWS_REGION_NAME']
    )
    
    Dir.glob("#{images_path}/*.jpg").each do |file_path|
      filename = File.basename(file_path)
      
      begin
        s3.put_object(
          bucket: bucket_name,
          key: filename,
          body: File.read(file_path),
          content_type: 'image/jpeg'
        )
        puts "Uploaded: #{filename}"
      rescue => e
        puts "Failed to upload #{filename}: #{e.message}"
      end
    end
  end
end