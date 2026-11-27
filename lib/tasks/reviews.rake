# frozen_string_literal: true

# Review request emails (docs/plans/2026-11-26-product-reviews-design.md, "Review request email flow").
# Scheduled hourly: Heroku Scheduler, or the k8s CronJob in k8-cronjob-reviews.yml. See HEROKU_DEPLOYMENT.md.
namespace :reviews do
  desc 'Send due review request emails and reminders, expire and complete requests, refresh AI summaries (hourly; idempotent)'
  task dispatch: :environment do
    dispatch = ReviewRequests::Dispatch.new
    counts = dispatch.call
    puts "reviews:dispatch #{counts.map { |name, count| "#{name}=#{count}" }.join(' ')} " \
         "ai_summaries=#{dispatch.summary_trigger || 'skipped'}"
  end

  desc 'Schedule review requests for orders shipped in the last N days (default 30) that have none'
  task :backfill, [:days] => :environment do |_task, args|
    days = (args[:days].presence || 30).to_i
    unless Spree::ReviewSetting.current.enabled
      puts 'reviews:backfill skipped: reviews are switched off (Reviews > Settings)'
      next
    end

    count = ReviewRequests::Backfill.call(days: days)
    puts "reviews:backfill scheduled=#{count} days=#{days}"
  end
end
