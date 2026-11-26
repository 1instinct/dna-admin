class CreatePushSubscriptions < ActiveRecord::Migration[6.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: { to_table: :spree_users }
      t.string :token, null: false
      t.string :platform, null: false # ios, android
      t.string :device_name
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end

    add_index :push_subscriptions, :token, unique: true
    add_index :push_subscriptions, :platform
    add_index :push_subscriptions, :enabled
  end
end
