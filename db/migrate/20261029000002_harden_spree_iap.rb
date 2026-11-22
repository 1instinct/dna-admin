# Security hardening for in-app purchases:
# - store_signed_at: newest store signature applied to a transaction, so older
#   (replayed or retried) payloads never overwrite newer state.
# - account_token: appAccountToken / obfuscatedExternalAccountId carried by
#   the purchase, which binds it to the account that bought it.
# - spree_iap_account_tokens: one stable UUID per user handed to the app.
class HardenSpreeIap < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_iap_transactions, :store_signed_at, :datetime
    add_column :spree_iap_transactions, :account_token, :string
    add_index :spree_iap_transactions, :account_token

    create_table :spree_iap_account_tokens do |t|
      t.references :user, null: false, index: { unique: true }
      t.string :token, null: false
      t.timestamps
    end
    add_index :spree_iap_account_tokens, :token, unique: true
  end
end
