class CreateSpreeDigitalAssets < ActiveRecord::Migration[6.1]
  def change
    # A versioned set of files sold as a variant. spree_variants.id is a serial (integer) column.
    create_table :spree_digital_assets do |t|
      t.references :variant, type: :integer, null: false, index: true, foreign_key: { to_table: :spree_variants }
      t.string :kind, null: false
      t.integer :version
      t.string :status, null: false, default: 'draft'
      t.jsonb :manifest, null: false, default: {}
      t.bigint :byte_size, null: false, default: 0

      t.timestamps
    end
    add_index :spree_digital_assets, %i[variant_id version], unique: true, where: 'version IS NOT NULL',
                                                             name: 'index_spree_digital_assets_on_variant_version'
    add_index :spree_digital_assets, %i[variant_id status]

    # Who owns which variant, and why. At most one active (unrevoked) row per user and variant.
    create_table :spree_digital_ownerships do |t|
      t.references :user, type: :integer, null: false, index: true, foreign_key: { to_table: :spree_users }
      t.references :variant, type: :integer, null: false, index: true, foreign_key: { to_table: :spree_variants }
      t.string :source, null: false
      t.string :source_type
      t.bigint :source_id
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.string :revoke_reason

      t.timestamps
    end
    add_index :spree_digital_ownerships, %i[user_id variant_id], unique: true, where: 'revoked_at IS NULL',
                                                                 name: 'index_spree_digital_ownerships_active'
    add_index :spree_digital_ownerships, %i[source_type source_id]
  end
end
