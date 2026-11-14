namespace :uploads do
  desc 'Purge uploaded blobs that were never attached and are more than a day old'
  task sweep_unattached: :environment do
    puts "Purged #{Uploads::UnattachedSweeper.call} unattached blobs"
  end
end
