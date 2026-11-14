namespace :affiliates do
  desc 'Approve pending affiliate commissions whose hold has passed (run daily from a scheduler)'
  task sweep: :environment do
    count = AffiliateCommission.sweep!
    puts "affiliates:sweep approved #{count} commission(s)"
  end
end
