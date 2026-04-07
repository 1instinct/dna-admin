class CreateLiveStreamContacts < ActiveRecord::Migration[6.1]
  def change
    create_table :live_stream_contacts do |t|
      t.references :live_stream, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true

      t.timestamps
    end
  end
end
