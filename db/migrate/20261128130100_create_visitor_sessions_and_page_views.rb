# One storefront visit: pings from the widget extend it, and 30 minutes without one end it
# (Visitors::Tracker). ip is stored truncated (/24 for IPv4, /48 for IPv6).
class CreateVisitorSessionsAndPageViews < ActiveRecord::Migration[6.1]
  def change
    create_table :visitor_sessions do |t|
      t.bigint :contact_id, null: false
      t.string :token, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.text :current_url
      t.string :current_title
      t.text :referrer
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.text :user_agent
      t.string :device
      t.string :ip
      t.string :country
      t.bigint :order_id
      t.integer :page_views, null: false, default: 0
      t.timestamps
    end
    add_index :visitor_sessions, :token, unique: true
    add_index :visitor_sessions, %i[contact_id last_seen_at]
    add_index :visitor_sessions, :last_seen_at
    add_index :visitor_sessions, :order_id
    add_foreign_key :visitor_sessions, :contacts, on_delete: :cascade
    add_foreign_key :visitor_sessions, :spree_orders, column: :order_id, on_delete: :nullify

    create_table :visitor_page_views do |t|
      t.bigint :visitor_session_id, null: false
      t.text :url, null: false
      t.string :title
      t.datetime :created_at, null: false
    end
    add_index :visitor_page_views, %i[visitor_session_id created_at]
    add_index :visitor_page_views, :created_at
    add_foreign_key :visitor_page_views, :visitor_sessions, on_delete: :cascade
  end
end
