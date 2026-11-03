class CreateSpreeUserBlocks < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_user_blocks do |t|
      t.integer :blocker_id, null: false
      t.integer :blocked_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :spree_user_blocks, %i[blocker_id blocked_id], unique: true
    add_index :spree_user_blocks, :blocked_id
    add_foreign_key :spree_user_blocks, :spree_users, column: :blocker_id
    add_foreign_key :spree_user_blocks, :spree_users, column: :blocked_id
  end
end
