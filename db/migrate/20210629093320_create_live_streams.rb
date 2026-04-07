class CreateLiveStreams < ActiveRecord::Migration[6.1]
  def change
    create_table :live_streams do |t|
      t.string :title
      t.text :description
      t.string :stream_url
      t.string :stream_key
      t.string :stream_id
      t.text :playback_ids, array: :true, default: []
      t.string :status
      t.datetime :start_date
      t.boolean :is_active

      t.timestamps
    end
  end
end
