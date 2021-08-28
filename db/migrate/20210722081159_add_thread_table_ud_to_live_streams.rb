class AddThreadTableUdToLiveStreams < ActiveRecord::Migration[6.1]
  def change
    add_reference :live_streams, :thread_table, null: true, foreign_key: true
  end
end
