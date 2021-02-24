#
# Place all seeds in /seeds/ folder.
#
Dir[File.dirname(__FILE__) + '/seeds/*.rb'].sort.each do |file|
  puts "Seeds #{file} ..."
  require file
end


Spree::Core::Engine.load_seed if defined?(Spree::Core)
Spree::Auth::Engine.load_seed if defined?(Spree::Auth)

unless Contact.count > 0
  load_seed('contacts').each do |s|
    Contact.create(s)
  end
  puts("Created Contact on #{Rails.env} environment")
end

unless Message.count > 0
  load_seed('messages').each do |s|
    Message.create(s)
  end
  puts("Created messages on #{Rails.env} environment")
end
