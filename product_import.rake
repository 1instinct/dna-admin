require 'csv'

namespace :products do
  desc "Import products from CSV"
  task import: :environment do
    file_path = ENV['CSV_FILE'] || Rails.root.join('db', 'products.csv')
    images_path = ENV['IMAGES_PATH'] || '/Users/jon/Desktop/seed_examples'
    
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
      
      # Attach image if exists
      if row['image_file']
        image_file = File.join(images_path, row['image_file'])
        if File.exist?(image_file)
          product.images.create!(
            attachment: {
              io: File.open(image_file),
              filename: row['image_file']
            },
            alt: product.name
          )
          puts "Attached image: #{row['image_file']}"
        else
          puts "Image not found: #{image_file}"
        end
      end
      
      puts "Imported: #{product.name} (SKU: #{variant.sku})"
    end
  end
end