require 'csv'

namespace :products do
  desc "Import products from CSV with existing S3 images"
  task import_with_s3: :environment do
    file_path = ENV['CSV_FILE'] || Rails.root.join('db', 'seed_data', 'products.csv')
    bucket_name = ENV['AWS_BUCKET_NAME'] || 'dna-admin-dev-jon-12345'
    
    # Get default shipping category
    shipping_category = Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: 'Default')
    
    CSV.foreach(file_path, headers: true) do |row|
      product = Spree::Product.find_or_create_by(name: row['name']) do |p|
        p.price = row['price']
        p.description = row['description']
        p.available_on = Time.current
        p.shipping_category = shipping_category
      end
      
      product.save! if product.new_record?
      
      # Create variant with SKU
      variant = product.variants.find_or_create_by(sku: row['sku']) do |v|
        v.price = row['price']
      end
      
      # Reference existing S3 image
      if row['image_file'] && !product.images.any?
        s3_url = "https://#{bucket_name}.s3.amazonaws.com/#{row['image_file']}"
        
        begin
          downloaded_image = URI.open(s3_url)
          product.images.create!(
            attachment: {
              io: downloaded_image,
              filename: row['image_file']
            },
            alt: product.name
          )
          puts "Attached S3 image: #{row['image_file']}"
        rescue => e
          puts "Failed to attach S3 image #{row['image_file']}: #{e.message}"
        end
      end
      
      puts "Imported: #{product.name} (SKU: #{variant.sku})"
    end
  end
end