class CreateSpreeUserProfiles < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_user_profiles do |t|
      t.integer :user_id, null: false
      t.string :handle
      t.string :name, limit: 40
      t.text :bio
      t.string :website, limit: 200
      t.jsonb :links, null: false, default: {}
      t.string :visibility, null: false, default: 'public'
      t.datetime :handle_changed_at
      t.datetime :hidden_at
      t.string :hidden_reason
      t.timestamps

      t.index :user_id, unique: true
      # Handles are stored lowercase; the expression index also guards against mixed-case writes.
      t.index 'lower((handle)::text)', unique: true, name: 'index_spree_user_profiles_on_lower_handle'
    end

    add_foreign_key :spree_user_profiles, :spree_users, column: :user_id
  end
end
