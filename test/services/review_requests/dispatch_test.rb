require 'test_helper'
require 'rake'
require 'minitest/mock'

# M4.3: `rake reviews:dispatch` (ReviewRequests::Dispatch) and `rake reviews:backfill`.
class ReviewRequests::DispatchTest < ActiveSupport::TestCase
  setup do
    reviews_enable!
    review_requests_home!
    ActionMailer::Base.deliveries.clear
    @top = media_product(name: 'Wrap Top')
    @skirt = media_product(name: 'Slip Skirt')
    @order = review_requests_order(@top, @skirt, email: 'maya@example.com')
    @now = Time.current
  end

  def dispatch(now = @now)
    ReviewRequests::Dispatch.call(now: now)
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  # The raw token from a delivered email's opt-out link.
  def token_in(mail)
    mail.text_part.body.to_s[%r{/review/([\w-]+)\?opt_out=1}, 1]
  end

  test 'a due request is sent once, however often the task runs' do
    request, = review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    review_request_for(review_requests_order(@top), status: 'scheduled', send_after: 1.day.from_now)

    assert_equal 1, dispatch[:sent]
    assert_equal 0, dispatch[:sent]
    assert_equal 0, dispatch(@now + 1.hour)[:sent]
    assert_equal 1, deliveries.size
    assert_equal ['maya@example.com'], deliveries.first.to

    request.reload
    assert_equal 'sent', request.status
    assert_in_delta @now, request.sent_at, 1
    assert_equal request, Spree::ReviewRequest.find_by_token(token_in(deliveries.first)), 'the emailed link works'
  end

  test 'one reminder, only when nothing has been reviewed, with a new link' do
    request, = review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    dispatch
    first_token = token_in(deliveries.last)

    assert_equal 0, dispatch(@now + 6.days)[:reminded], 'not before reminder_delay_days'
    assert_equal 1, dispatch(@now + 7.days)[:reminded]
    assert_equal 0, dispatch(@now + 8.days)[:reminded]
    assert_equal 2, deliveries.size
    assert_equal "Reminder: how's your Test Store order?", deliveries.last.subject
    assert_equal 'reminded', request.reload.status
    assert_nil Spree::ReviewRequest.find_by_token(first_token), 'only the latest link works'
    assert_equal request, Spree::ReviewRequest.find_by_token(token_in(deliveries.last))

    started, = review_request_for(review_requests_order(@top, @skirt), status: 'sent', sent_at: @now - 8.days)
    reviews_submit(@top, review_request: started, rating: 2)
    assert_equal 0, dispatch[:reminded]
    assert_equal 'sent', started.reload.status
  end

  test 'expiry' do
    sent, = review_request_for(@order, status: 'sent', sent_at: @now - 61.days, expires_at: @now - 1.minute)
    scheduled, = review_request_for(review_requests_order(@top), status: 'scheduled', send_after: @now - 2.days,
                                                                 expires_at: @now - 1.day)
    assert_equal 2, dispatch[:expired]
    assert_equal %w[expired expired], [sent.reload.status, scheduled.reload.status]
    assert_empty deliveries
  end

  test 'completed once every item has a review' do
    request, = review_request_for(@order, status: 'sent', sent_at: @now - 1.day)
    reviews_submit(@top, review_request: request, rating: 5)
    assert_equal 0, dispatch[:completed]
    reviews_submit(@skirt, review_request: request, rating: 1)
    assert_equal 1, dispatch[:completed]
    assert_equal 'completed', request.reload.status
    assert_in_delta @now, request.completed_at, 1
  end

  test 'nothing left to ask about: completed or cancelled instead of sent' do
    reviewed_order = review_requests_order(@top, user: create(:user))
    reviewed, = review_request_for(reviewed_order, status: 'scheduled')
    reviews_submit(@top, user: reviewed_order.user, rating: 4)
    canceled, = review_request_for(review_requests_order(@top), status: 'scheduled')
    canceled.order.update_columns(state: 'canceled')
    out_order = review_requests_order(@top, email: 'out@example.com')
    review_request_for(review_requests_order(@skirt, email: 'OUT@example.com'), status: 'opted_out')
    opted_out, = review_request_for(out_order, status: 'scheduled')

    counts = dispatch
    assert_equal [0, 1, 2], counts.values_at(:sent, :completed, :cancelled)
    assert_equal %w[completed cancelled cancelled], [reviewed, canceled, opted_out].map { |r| r.reload.status }
    assert_empty deliveries
  end

  test 'a failed delivery leaves the request to retry on the next run' do
    request, = review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    failing = Object.new
    failing.define_singleton_method(:deliver_now) { raise Net::SMTPServerBusy, 'try later' }

    counts = ReviewRequestMailer.stub(:request_review, failing) { dispatch }
    assert_equal [0, 1], counts.values_at(:sent, :failed)
    request.reload
    assert_equal 'scheduled', request.status
    assert_nil request.sent_at
    assert_nil request.token_digest, 'the new token was rolled back too'

    assert_equal 1, dispatch[:sent]
    assert_equal 'sent', request.reload.status
  end

  test 'nothing is sent while reviews are switched off; expiry still runs' do
    review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    old, = review_request_for(review_requests_order(@top), status: 'sent', expires_at: 1.minute.ago)
    reviews_enable!(enabled: false)
    counts = dispatch
    assert_equal [0, 1], counts.values_at(:sent, :expired)
    assert_equal 'expired', old.reload.status
    assert_empty deliveries
  end

  # Another run holding the row lock: FOR UPDATE SKIP LOCKED returns nothing, so this run moves on.
  module LockedElsewhere
    def lock(*)
      none
    end
  end

  test 'a request another run holds is skipped' do
    request, = review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    held = ->(*) { Spree::ReviewRequest.where(id: request.id).extending(LockedElsewhere) }
    counts = Spree::ReviewRequest.stub(:due, held) { dispatch }
    assert_equal [0, 0], counts.values_at(:sent, :failed)
    assert_empty deliveries
    assert_equal 'scheduled', request.reload.status
  end

  test 'backfill: orders shipped in the last N days without a request, due now' do
    recent = review_requests_order(@top, completed_at: 5.days.ago)
    old = review_requests_order(@top, completed_at: 40.days.ago)
    review_request_for(@order, status: 'sent')
    not_shipped = review_requests_order(@top, shipped: false)

    assert_equal 1, ReviewRequests::Backfill.call(days: 30, now: @now)
    request = Spree::ReviewRequest.find_by(order: recent)
    assert_equal ['scheduled', @now.to_i], [request.status, request.send_after.to_i]
    assert_nil Spree::ReviewRequest.find_by(order: old)
    assert_nil Spree::ReviewRequest.find_by(order: not_shipped)
    assert_equal 0, ReviewRequests::Backfill.call(days: 30, now: @now), 'safe to run again'
  end

  test 'backfill staggers big batches by the hour' do
    2.times { review_requests_order(@top, completed_at: 2.days.ago) }
    assert_equal 3, ReviewRequests::Backfill.call(days: 30, now: @now, per_hour: 2), 'with the order from setup'
    offsets = Spree::ReviewRequest.all.map { |request| (request.send_after - @now).round }.sort
    assert_equal [0, 0, 3600], offsets
  end

  test 'rake tasks print their counts' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('reviews:dispatch')
    review_request_for(@order, status: 'scheduled', send_after: 1.hour.ago)
    Rake::Task['reviews:dispatch'].reenable
    out, = capture_io { Rake::Task['reviews:dispatch'].invoke }
    assert_match(/reviews:dispatch sent=1 reminded=0 expired=0 completed=0 cancelled=0 failed=0/, out)

    review_requests_order(@skirt, completed_at: 3.days.ago)
    Rake::Task['reviews:backfill'].reenable
    out, = capture_io { Rake::Task['reviews:backfill'].invoke('10') }
    assert_match(/reviews:backfill scheduled=1 days=10/, out)
  end
end
