namespace :chat do
  desc 'Fill the chat columns on older contacts, threads and messages (run once after the chat migrations)'
  task backfill: :environment do
    counts = Chat::Backfill.run
    puts "chat:backfill #{counts.map { |name, count| "#{name}=#{count}" }.join(' ')}"
  end
end
