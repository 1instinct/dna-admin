class AddActorIdToLiveStreams < ActiveRecord::Migration[6.1]
  def change
    add_column :live_streams, :actor_id, :integer
  end
end
