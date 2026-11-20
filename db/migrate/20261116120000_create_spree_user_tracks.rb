class CreateSpreeUserTracks < ActiveRecord::Migration[6.1]
  def change
    # A backing track a user asked a generator for (Spree::UserTrack). Rows are soft-deleted
    # (deleted_at) so the monthly quota, the hourly limit and the daily spend breaker still count
    # them; the audio is purged at once.
    create_table :spree_user_tracks do |t|
      t.integer :user_id, null: false
      t.string :source, null: false, default: 'ai'
      t.string :status, null: false, default: 'queued'
      t.string :title
      # As asked: style, moods, bars, bpm, key, scale, timeSig.
      t.jsonb :request, null: false, default: {}
      # Provider, model, seeds, request ids, attempts, cost estimate, analysis of every attempt.
      t.jsonb :generation, null: false, default: {}
      # The track profile once ready (plus profileSource, keyConfidence, keyNote).
      t.jsonb :profile
      # { sampleRate, loopSamples } of the stored loop.
      t.jsonb :loop_info
      t.text :error
      # Part of the provider webhook URL ("<id>-<secret>"), compared in constant time.
      t.string :webhook_secret, null: false
      t.datetime :submitted_at
      t.datetime :checked_at
      t.datetime :ready_at
      t.datetime :credit_refunded_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :spree_user_tracks, %i[user_id created_at]
    add_index :spree_user_tracks, %i[status submitted_at]
    add_index :spree_user_tracks, :created_at
    add_foreign_key :spree_user_tracks, :spree_users, column: :user_id, on_delete: :cascade
  end
end
