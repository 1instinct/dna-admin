namespace :marketplace do
  desc 'Daily marketplace upkeep: creator earnings and affiliate commissions past their hold, stale uploads'
  task sweep: :environment do
    puts "marketplace:sweep made #{Spree::CreatorEarning.sweep!} creator earning(s) payable"

    # The affiliates module is optional. safe_constantize (rather than defined?) also autoloads
    # the class under the classic autoloader.
    if (commissions = 'AffiliateCommission'.safe_constantize)
      puts "marketplace:sweep approved #{commissions.sweep!} affiliate commission(s)"
    end

    Rake::Task['uploads:sweep_unattached'].invoke if Rake::Task.task_defined?('uploads:sweep_unattached')
  end
end
