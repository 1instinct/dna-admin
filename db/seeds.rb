#
# Place all seeds in /seeds/ folder.
#

Dir[File.dirname(__FILE__) + '/spree_seeds/*.rb'].sort.each do |file|
  puts "Seeds #{file} ..."
  require file
end

Spree::Sample.load_sample("products")

explicit_seeds = %w[stores.rb sample_products.rb]
Dir[File.dirname(__FILE__) + '/seeds/*.rb'].sort.each do |file|
  next if explicit_seeds.include?(File.basename(file))
  puts "Seeds #{file} ..."
  require file
end

# Multi-market stores
load Rails.root.join("db/seeds/stores.rb")

# Sample products (dev only)
load Rails.root.join("db/seeds/sample_products.rb")