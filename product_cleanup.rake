namespace :products do
  desc "Remove sample products, keep only imported ones"
  task cleanup: :environment do
    # Keep products with your specific names
    keep_products = ["Blue Cotton Shirt", "Black Jeans"]
    
    # Delete all other products
    Spree::Product.where.not(name: keep_products).destroy_all
    
    puts "Cleaned up products. Kept: #{keep_products.join(', ')}"
    puts "Total products remaining: #{Spree::Product.count}"
  end
end