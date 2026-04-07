class CreateLiveStreamProducts < ActiveRecord::Migration[6.1]
  def change
    create_table :live_stream_products do |t|
      t.references :live_stream
      t.references :product

      t.timestamps
    end
  end
end
