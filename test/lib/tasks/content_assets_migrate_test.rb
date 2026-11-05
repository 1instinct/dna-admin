require 'test_helper'
require 'rake'
require 'minitest/mock'

class ContentAssetsMigrateTaskTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('content_assets:migrate_existing')
    @task = Rake::Task['content_assets:migrate_existing']
    @task.reenable
  end

  test "aborts instead of writing relative URLs when no host is configured" do
    Rails.application.routes.stub(:default_url_options, {}) do
      _out, err = capture_io do
        assert_raises(SystemExit) { @task.invoke }
      end
      assert_match(/no host configured/, err)
    end
  end

  test "runs when a host is configured" do
    out, _err = capture_io { @task.invoke }
    assert_match(/Migration Summary/, out)
  end

  test "writes absolute proxy URLs" do
    asset = create(:content_asset)
    assert_match %r{\Ahttp://localhost/rails/active_storage/blobs/proxy/}, absolute_asset_url(asset)
  end

  test "only downloads http(s) URLs" do
    %w[ftp://example.com/a.png file:///etc/passwd].each do |url|
      assert_raises(ContentAssetDownloadError) { fetch_remote_file(url) }
    end
  end
end
