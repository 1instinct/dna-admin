namespace :visitors do
  desc 'Delete storefront page views older than 30 days (Visitors.config.page_view_retention; run daily from a scheduler)'
  task prune: :environment do
    count = Visitors.prune!
    puts "visitors:prune deleted #{count} page view(s)"
  end
end
