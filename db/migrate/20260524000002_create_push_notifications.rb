class CreatePushNotifications < ActiveRecord::Migration[6.1]
  def change
    create_table :push_notifications do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :notification_type, default: 'custom' # custom, product, order, promo
      t.jsonb :data, default: {}
      t.string :target, default: 'all' # all, segment, user
      t.bigint :target_user_id
      t.integer :sent_count, default: 0
      t.integer :error_count, default: 0
      t.text :errors_log
      t.string :status, default: 'draft' # draft, sent, failed
      t.references :sent_by, foreign_key: { to_table: :spree_users }
      t.timestamps
    end

    add_index :push_notifications, :notification_type
    add_index :push_notifications, :status
    add_index :push_notifications, :target
  end
end
