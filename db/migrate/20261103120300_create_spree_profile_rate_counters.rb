class CreateSpreeProfileRateCounters < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_profile_rate_counters do |t|
      t.integer :user_id, null: false
      t.string :action, null: false
      t.datetime :window_started_at, null: false
      t.integer :hits, null: false, default: 0
    end

    add_index :spree_profile_rate_counters, %i[user_id action], unique: true
  end
end
