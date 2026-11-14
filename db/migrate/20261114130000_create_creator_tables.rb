# Creators: applications to sell, the accounts of approved creators, and a creator's products
# (ordinary Spree products with creator_id and a review state).
class CreateCreatorTables < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_creator_applications do |t|
      t.references :user, type: :integer, null: false, index: true, foreign_key: { to_table: :spree_users }
      t.string :status, null: false, default: 'pending'
      t.string :display_name, null: false
      t.string :kinds, array: true, null: false, default: []
      t.jsonb :portfolio_links, null: false, default: []
      t.text :about
      t.integer :reviewed_by_id
      t.datetime :reviewed_at
      t.text :review_note

      t.timestamps
    end
    add_index :spree_creator_applications, :user_id, unique: true, where: "status = 'pending'",
                                                     name: 'index_spree_creator_applications_one_pending'
    add_index :spree_creator_applications, %i[status created_at]

    create_table :spree_creator_accounts do |t|
      t.references :user, type: :integer, null: false, index: { unique: true }, foreign_key: { to_table: :spree_users }
      t.integer :revenue_share_bps, null: false
      t.string :payout_email
      t.text :payout_notes
      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    add_reference :spree_products, :creator, type: :integer, index: true, foreign_key: { to_table: :spree_users }
    add_column :spree_products, :review_state, :string
    add_column :spree_products, :review_note, :text
    add_column :spree_products, :submitted_at, :datetime
    add_index :spree_products, :review_state
  end
end
