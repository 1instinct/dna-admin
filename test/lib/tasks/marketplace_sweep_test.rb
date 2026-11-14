require 'test_helper'
require 'rake'

class MarketplaceSweepTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('marketplace:sweep')
    @task = Rake::Task['marketplace:sweep']
    @task.reenable
    Rake::Task['uploads:sweep_unattached'].reenable
  end

  test 'makes due creator earnings payable and purges stale unattached uploads' do
    account = create(:creator_account)
    due = create(:creator_earning, creator_account: account, payable_at: 1.minute.ago)
    later = create(:creator_earning, creator_account: account, payable_at: 1.day.from_now)
    stale = digital_blob
    stale.update_columns(created_at: 2.days.ago)

    out, _err = capture_io { @task.invoke }

    assert_match(/1 creator earning/, out)
    assert_equal 'payable', due.reload.state
    assert_equal 'pending', later.reload.state
    refute ActiveStorage::Blob.exists?(stale.id)
  end
end
