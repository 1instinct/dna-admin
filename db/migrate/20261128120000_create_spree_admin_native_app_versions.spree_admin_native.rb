# This migration comes from spree_admin_native (originally 20261128000001)
class CreateSpreeAdminNativeAppVersions < ActiveRecord::Migration[6.1]
  # Idempotent like the first migration: hosts that install the gem's migrations at every boot copy
  # it again under a new timestamp.
  def change
    create_table :spree_admin_native_app_versions, if_not_exists: true do |t|
      t.string :platform, null: false # ios, android or all
      t.string :minimum_version
      t.string :recommended_version
      t.string :update_url
      t.boolean :allow_ahead_of_store, null: false, default: false
      t.timestamps
    end
    add_index :spree_admin_native_app_versions, :platform, unique: true, if_not_exists: true
  end
end
