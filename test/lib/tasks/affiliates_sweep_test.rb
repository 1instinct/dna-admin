require 'test_helper'
require 'rake'

class AffiliatesSweepTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('affiliates:sweep')
    @task = Rake::Task['affiliates:sweep']
    @task.reenable
  end

  test 'approves pending commissions past their hold' do
    due = create(:affiliate_commission, approvable_at: 1.minute.ago)
    later = create(:affiliate_commission, approvable_at: 1.day.from_now)
    out, _err = capture_io { @task.invoke }
    assert_match(/approved 1 commission/, out)
    assert_equal 'approved', due.reload.state
    assert_equal 'pending', later.reload.state
  end
end
