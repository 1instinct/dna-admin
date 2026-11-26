# This migration comes from spree_admin_native (originally 20261126000001)
class CreateSpreeAdminNativeTables < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_admin_native_devices do |t|
      # Polymorphic: Spree 4.x admins are Spree::User, Spree 5+/6 admins are Spree::AdminUser.
      t.references :owner, polymorphic: true, null: false, index: true
      t.string :name, null: false
      t.string :platform
      t.string :token_digest, null: false
      t.string :push_token
      t.boolean :push_enabled, null: false, default: true
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :spree_admin_native_devices, :token_digest, unique: true

    create_table :spree_admin_native_pairings do |t|
      t.references :owner, polymorphic: true, null: false, index: true
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.references :device, index: false
      t.timestamps
    end
    add_index :spree_admin_native_pairings, :code_digest, unique: true
  end
end
