class CreateLiveStreamLikes < ActiveRecord::Migration[6.1]
  def change
    create_table :live_stream_likes do |t|
      t.references :live_stream
      t.references :user

      t.timestamps
    end
  end
end
