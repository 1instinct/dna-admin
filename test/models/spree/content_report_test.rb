require 'test_helper'

class Spree::ContentReportTest < ActiveSupport::TestCase
  setup do
    @reporter = create(:user)
    @profile = create(:user_profile, handle: 'target', name: 'Target', bio: 'hello', website: 'https://example.com')
  end

  test 'reason must be in the list' do
    Spree::ContentReport::REASONS.each do |reason|
      assert build(:content_report, reporter: @reporter, reportable: @profile, reason: reason).valid?, reason
    end
    refute build(:content_report, reporter: @reporter, reportable: @profile, reason: 'boring').valid?
  end

  test 'details at most 500 chars' do
    refute build(:content_report, reporter: @reporter, reportable: @profile, details: 'd' * 501).valid?
    assert build(:content_report, reporter: @reporter, reportable: @profile, details: 'd' * 500).valid?
  end

  test 'status defaults to open and must be known' do
    report = create(:content_report, reporter: @reporter, reportable: @profile)
    assert_equal 'open', report.status
    report.status = 'whatever'
    refute report.valid?
  end

  test 'for_profile stores a snapshot of the reported fields' do
    report = Spree::ContentReport.for_profile(@profile, reporter: @reporter, reason: 'spam', details: 'ads')
    report.save!
    snap = report.reload.snapshot
    assert_equal 'target', snap['handle']
    assert_equal 'Target', snap['name']
    assert_equal 'hello', snap['bio']
    assert_equal 'https://example.com', snap['website']
    assert_equal false, snap['avatar']
  end

  test 'the 21st report by one reporter in 24 hours is invalid' do
    20.times { create(:content_report, reporter: @reporter, reportable: @profile) }
    report = build(:content_report, reporter: @reporter, reportable: @profile)
    refute report.valid?
    assert report.rate_limited?

    Spree::ContentReport.where(reporter_id: @reporter.id).update_all(created_at: 25.hours.ago)
    assert build(:content_report, reporter: @reporter, reportable: @profile).valid?
  end

  test 'resolve! records resolver, time and note' do
    admin = create(:user)
    report = create(:content_report, reporter: @reporter, reportable: @profile)
    report.resolve!(status: 'actioned', by: admin, note: 'hid it')
    report.reload
    assert_equal 'actioned', report.status
    assert_equal admin.id, report.resolved_by_id
    assert report.resolved_at.present?
    assert_equal 'hid it', report.resolution_note
  end
end
