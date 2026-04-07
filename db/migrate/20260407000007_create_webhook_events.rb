class CreateWebhookEvents < ActiveRecord::Migration[6.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :webhook_events, id: :uuid do |t|
      t.string :event_type, null: false
      t.integer :source, null: false
      t.jsonb :payload, default: {}
      t.string :correlation_id
      t.datetime :processed_at
      t.text :error

      t.timestamps
    end

    add_index :webhook_events, :event_type
    add_index :webhook_events, :source
    add_index :webhook_events, :correlation_id
    add_index :webhook_events, :created_at
  end
end
