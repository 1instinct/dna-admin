# Product and store reviews, review request emails, per-channel rating stats, per-category review
# questions, product Q&A and the review settings singleton. See
# docs/plans/2026-11-26-product-reviews-design.md.
#
# Spree's own tables use serial (integer) ids, so every reference to them is type: :integer.
class CreateSpreeReviews < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_review_settings do |t|
      # Always 0, unique: keeps the table to one row (see Spree::ReviewSetting.current).
      t.integer :singleton_guard, null: false, default: 0
      t.boolean :enabled, null: false, default: false
      t.boolean :store_reviews_enabled, null: false, default: false
      t.boolean :questions_enabled, null: false, default: false
      t.boolean :auto_publish, null: false, default: true
      t.boolean :photos_require_approval, null: false, default: true
      t.integer :request_delay_days, null: false, default: 7
      t.integer :international_request_delay_days, null: false, default: 10
      t.integer :reminder_delay_days, null: false, default: 7
      t.integer :request_expiry_days, null: false, default: 60
      t.integer :points_per_review, null: false, default: 50
      t.integer :points_photo_bonus, null: false, default: 50
      t.boolean :ai_summary_enabled, null: false, default: false
      t.integer :ai_summary_min_reviews, null: false, default: 5
      t.timestamps
    end
    add_index :spree_review_settings, :singleton_guard, unique: true

    create_table :spree_review_requests do |t|
      t.references :order, type: :integer, null: false, index: { unique: true },
                           foreign_key: { to_table: :spree_orders }
      t.references :user, type: :integer, index: true, foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.string :email, null: false
      # SHA256 of the token in the email link; the raw token is never stored.
      t.string :token_digest
      t.string :status, null: false, default: 'scheduled'
      t.datetime :send_after, null: false
      t.datetime :sent_at
      t.datetime :reminded_at
      t.datetime :opened_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.timestamps
    end
    add_index :spree_review_requests, :token_digest, unique: true
    add_index :spree_review_requests, %i[status send_after]

    create_table :spree_reviews do |t|
      t.string :reviewable_type, null: false
      t.integer :reviewable_id, null: false
      t.references :variant, type: :integer, index: true, foreign_key: { to_table: :spree_variants, on_delete: :nullify }
      t.references :user, type: :integer, index: true, foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.references :order, type: :integer, index: true, foreign_key: { to_table: :spree_orders, on_delete: :nullify }
      t.references :line_item, type: :integer, index: true,
                               foreign_key: { to_table: :spree_line_items, on_delete: :nullify }
      t.references :review_request, index: true, foreign_key: { to_table: :spree_review_requests, on_delete: :nullify }
      t.integer :rating, null: false
      t.string :title, limit: 120
      t.text :body
      t.jsonb :attribute_ratings, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.string :moderation_reason
      t.references :moderated_by, type: :integer, index: false,
                                  foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.datetime :moderated_at
      t.boolean :verified_purchase, null: false, default: true
      t.boolean :incentivized, null: false, default: false
      t.datetime :points_awarded_at
      t.string :source, null: false, default: 'web'
      t.string :channel, null: false, default: 'retail'
      t.string :display_name, null: false
      t.string :locale
      t.integer :helpful_count, null: false, default: 0
      t.integer :unhelpful_count, null: false, default: 0
      t.integer :reports_count, null: false, default: 0
      t.text :reply_body
      t.references :reply_author, type: :integer, index: false,
                                  foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.datetime :replied_at
      t.datetime :published_at
      t.datetime :edited_at
      t.string :ip_hash
      t.timestamps
    end
    add_index :spree_reviews, %i[reviewable_type reviewable_id status channel], name: 'index_spree_reviews_on_reviewable_status_channel'
    add_index :spree_reviews, %i[status created_at]
    # One review per product per signed-in user, and per product per order (guest token flow).
    add_index :spree_reviews, %i[user_id reviewable_type reviewable_id], unique: true, where: 'user_id IS NOT NULL',
                                                                         name: 'index_spree_reviews_one_per_user'
    add_index :spree_reviews, %i[order_id reviewable_type reviewable_id], unique: true, where: 'order_id IS NOT NULL',
                                                                          name: 'index_spree_reviews_one_per_order'
    add_check_constraint :spree_reviews, 'rating BETWEEN 1 AND 5', name: 'spree_reviews_rating_range'

    create_table :spree_review_votes do |t|
      t.references :review, null: false, index: false, foreign_key: { to_table: :spree_reviews, on_delete: :cascade }
      t.references :user, type: :integer, index: true, foreign_key: { to_table: :spree_users, on_delete: :cascade }
      # SHA256 of "user:<id>" or of an anonymous visitor id: one vote per voter per review.
      t.string :voter_key, null: false
      t.boolean :helpful, null: false
      t.timestamps
    end
    add_index :spree_review_votes, %i[review_id voter_key], unique: true

    create_table :spree_review_stats do |t|
      t.string :reviewable_type, null: false
      t.integer :reviewable_id, null: false
      t.string :scope, null: false
      t.decimal :average, precision: 3, scale: 2, null: false, default: 0
      t.integer :ratings_count, null: false, default: 0
      t.integer :reviews_count, null: false, default: 0
      t.integer :photos_count, null: false, default: 0
      t.jsonb :histogram, null: false, default: {}
      t.jsonb :attribute_averages, null: false, default: {}
      t.jsonb :ai_summary
      t.integer :ai_summary_review_count
      t.datetime :ai_summary_generated_at
      t.boolean :ai_summary_hidden, null: false, default: false
      t.timestamps
    end
    add_index :spree_review_stats, %i[reviewable_type reviewable_id scope], unique: true,
                                                                            name: 'index_spree_review_stats_unique'

    create_table :spree_review_attributes do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :kind, null: false, default: 'scale'
      t.string :low_label
      t.string :high_label
      # product: asked about products in the attribute's taxons; store: asked in store reviews.
      t.string :applies_to, null: false, default: 'product'
      t.integer :position
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :spree_review_attributes, :key, unique: true

    create_table :spree_review_attributes_taxons, id: false do |t|
      t.references :review_attribute, null: false, index: false,
                                      foreign_key: { to_table: :spree_review_attributes, on_delete: :cascade }
      t.references :taxon, type: :integer, null: false, index: true,
                           foreign_key: { to_table: :spree_taxons, on_delete: :cascade }
    end
    add_index :spree_review_attributes_taxons, %i[review_attribute_id taxon_id], unique: true,
                                                                                 name: 'index_spree_review_attribute_taxons_unique'

    create_table :spree_product_questions do |t|
      t.references :product, type: :integer, null: false, index: false,
                             foreign_key: { to_table: :spree_products, on_delete: :cascade }
      t.references :user, type: :integer, index: true, foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.text :body, null: false
      t.string :display_name, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :answers_count, null: false, default: 0
      t.datetime :published_at
      t.timestamps
    end
    add_index :spree_product_questions, %i[product_id status]

    create_table :spree_product_answers do |t|
      t.references :question, null: false, index: true,
                              foreign_key: { to_table: :spree_product_questions, on_delete: :cascade }
      t.references :user, type: :integer, index: true, foreign_key: { to_table: :spree_users, on_delete: :nullify }
      t.text :body, null: false
      t.string :display_name, null: false
      t.boolean :official, null: false, default: false
      t.boolean :verified_buyer, null: false, default: false
      t.string :status, null: false, default: 'pending'
      t.integer :helpful_count, null: false, default: 0
      t.datetime :published_at
      t.timestamps
    end

    change_table :spree_products, bulk: true do |t|
      # Retail scope; what the storefront shows and sorts by. *_reviews_count counts every
      # published rating, star-only ones included (ReviewStat#ratings_count).
      t.decimal :avg_rating, precision: 3, scale: 2, null: false, default: 0
      t.integer :reviews_count, null: false, default: 0
      # All channels; what wholesale listings show.
      t.decimal :all_avg_rating, precision: 3, scale: 2, null: false, default: 0
      t.integer :all_reviews_count, null: false, default: 0
    end
    add_index :spree_products, :avg_rating
    add_index :spree_products, :reviews_count
  end
end
