require 'test_helper'

class Profiles::ContentFilterTest < ActiveSupport::TestCase
  def allowed?(text, mode)
    with_moderation_lists(blocked: ['badword', 'two words']) { Profiles::ContentFilter.allowed?(text, mode: mode) }
  end

  test 'blank text is allowed' do
    assert allowed?(nil, :words)
    assert allowed?('', :handle)
  end

  test 'handle mode matches substrings, ignoring underscores' do
    refute allowed?('mybadwordz', :handle)
    refute allowed?('bad_word', :handle)
    assert allowed?('goodword', :handle)
  end

  test 'words mode matches whole words, case-insensitive, with a plural s' do
    refute allowed?('what a Badword', :words)
    refute allowed?('badwords everywhere', :words)
    refute allowed?('these Two Words here', :words)
    assert allowed?('mybadwordz is one token', :words)
    assert allowed?('two of the words', :words)
  end

  test 'the shipped list loads' do
    Profiles.reset_config!
    assert Profiles.config.blocked_terms.any?
    assert Profiles.config.reserved_handles.include?('admin')
  end

  test 'app files in the moderation folder extend the lists' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'reserved_handles.yml'), ['admin'].to_yaml)
      File.write(File.join(dir, 'myapp_reserved_handles.yml'), ['MyBrand'].to_yaml)
      File.write(File.join(dir, 'blocked_terms.yml'), ['badword'].to_yaml)
      File.write(File.join(dir, 'myapp_blocked_terms.yml'), ['other'].to_yaml)
      config = Profiles::Config.new
      config.moderation_dir = dir
      config.extra_reserved_handles = ['Extra']
      assert_equal Set.new(%w[admin mybrand extra]), config.reserved_handles
      assert_equal %w[badword other], config.blocked_terms
    end
  end
end
