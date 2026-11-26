# A creator's product is an ordinary Spree product with creator_id and a review state.
# spree_products is a large, busy table: the indexes build concurrently (outside a transaction) and
# the foreign key is added unvalidated, then validated, so neither blocks writes for long.
# Each step is skipped when already done (an earlier revision of CreateCreatorTables added the
# columns), so the migration is safe to run on any database.
class AddCreatorColumnsToSpreeProducts < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!

  # Lock waits give up after 5 s (the release phase fails and can be retried) instead of queueing
  # every request on spree_products behind a migration stuck on a long transaction. The concurrent
  # index builds run without the timeout: one that timed out would leave an invalid index, which
  # index_exists? would then skip on the retry.
  def up
    execute "SET lock_timeout = '5s'"
    add_column :spree_products, :creator_id, :integer unless column_exists?(:spree_products, :creator_id)
    add_column :spree_products, :review_state, :string unless column_exists?(:spree_products, :review_state)
    add_column :spree_products, :review_note, :text unless column_exists?(:spree_products, :review_note)
    add_column :spree_products, :submitted_at, :datetime unless column_exists?(:spree_products, :submitted_at)

    without_lock_timeout { add_index :spree_products, :creator_id, algorithm: :concurrently unless index_exists?(:spree_products, :creator_id) }
    without_lock_timeout { add_index :spree_products, :review_state, algorithm: :concurrently unless index_exists?(:spree_products, :review_state) }

    return if foreign_key_exists?(:spree_products, :spree_users, column: :creator_id)

    add_foreign_key :spree_products, :spree_users, column: :creator_id, validate: false
    validate_foreign_key :spree_products, :spree_users, column: :creator_id
  ensure
    execute 'RESET lock_timeout'
  end

  def without_lock_timeout
    execute 'SET lock_timeout = 0'
    yield
  ensure
    execute "SET lock_timeout = '5s'"
  end

  def down
    remove_foreign_key :spree_products, column: :creator_id if foreign_key_exists?(:spree_products, :spree_users, column: :creator_id)
    remove_index :spree_products, :review_state, algorithm: :concurrently if index_exists?(:spree_products, :review_state)
    remove_index :spree_products, :creator_id, algorithm: :concurrently if index_exists?(:spree_products, :creator_id)
    %i[submitted_at review_note review_state creator_id].each do |column|
      remove_column :spree_products, column if column_exists?(:spree_products, column)
    end
  end
end
