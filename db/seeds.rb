#
# Place all seeds in /seeds/ folder.
#

Dir[File.dirname(__FILE__) + '/spree_seeds/*.rb'].sort.each do |file|
  puts "Seeds #{file} ..."
  require file
end

Spree::Sample.load_sample("products")

Dir[File.dirname(__FILE__) + '/seeds/*.rb'].sort.each do |file|
  puts "Seeds #{file} ..."
  require file
end