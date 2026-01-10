class CreateUserFollows < ActiveRecord::Migration[6.1]
  def change
    create_table :user_follows do |t|
      t.integer :follower_id, null: false
      t.integer :following_id, null: false

      t.timestamps
    end
    
    add_index :user_follows, :follower_id
    add_index :user_follows, :following_id
    add_index :user_follows, [:follower_id, :following_id], unique: true, name: 'index_user_follows_on_follower_and_following'
  end
end
