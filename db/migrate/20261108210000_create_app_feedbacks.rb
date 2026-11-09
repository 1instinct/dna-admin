class CreateAppFeedbacks < ActiveRecord::Migration[6.1]
  def change
    create_table :app_feedbacks do |t|
      t.integer :user_id
      t.string :install_id
      t.string :email
      t.string :kind, null: false
      t.integer :rating
      t.string :moment
      t.text :message
      t.string :platform
      t.string :os_version
      t.string :device_model
      t.string :app_version
      t.string :build_number
      t.string :channel
      t.string :locale
      t.jsonb :diagnostics
      t.string :sentry_event_id
      t.string :status, null: false, default: 'new'
      t.text :admin_note
      t.timestamps
    end

    add_index :app_feedbacks, :user_id
    add_index :app_feedbacks, :install_id
    add_index :app_feedbacks, %i[status created_at]
    add_index :app_feedbacks, %i[kind created_at]
    add_foreign_key :app_feedbacks, :spree_users, column: :user_id, on_delete: :nullify

    # Fixed-window counters for AppFeedback::RateLimit, one row per key ("user:1", "install:…",
    # "ip:<hmac>"); IPs are stored only as an HMAC.
    create_table :app_feedback_rate_counters do |t|
      t.string :key, null: false
      t.datetime :window_started_at, null: false
      t.integer :hits, null: false, default: 0
    end

    add_index :app_feedback_rate_counters, :key, unique: true
    add_index :app_feedback_rate_counters, :window_started_at
  end
end
