require 'test_helper'

# The migration alters a busy table: lock waits give up after 5 s instead of queueing every
# request behind it. Concurrent index builds run without the timeout (a timed-out CREATE INDEX
# CONCURRENTLY leaves an invalid index that index_exists? would then skip), and the session
# setting is reset when the migration ends.
class AddAffiliateAttributionToSpreeOrdersMigrationTest < ActiveSupport::TestCase
  test 'up sets lock_timeout first, exempts concurrent index builds and resets it' do
    source = Rails.root.join('db', 'migrate', '20261114140100_add_affiliate_attribution_to_spree_orders.rb').read
    up = source[/def up\n(.*?)\n  def down/m, 1]
    assert up, 'has an up method'
    assert_equal %(execute "SET lock_timeout = '5s'"), up.lines.first.strip
    assert_match(/ensure\n\s+execute 'RESET lock_timeout'/, up)
    concurrent = up.scan(/^.*algorithm: :concurrently.*$/)
    assert_not_empty concurrent
    concurrent.each { |line| assert_match(/without_lock_timeout \{/, line) }
  end
end
