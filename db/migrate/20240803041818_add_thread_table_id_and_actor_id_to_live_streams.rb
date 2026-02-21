class AddThreadTableIdAndActorIdToLiveStreams < ActiveRecord::Migration[6.1]
  def change
    add_column :live_streams, :thread_table_id, :bigint unless column_exists?(:live_streams, :thread_table_id)
    add_foreign_key :live_streams, :thread_tables, column: :thread_table_id unless foreign_key_exists?(:live_streams, :thread_tables, column: :thread_table_id)
    add_column :live_streams, :actor_id, :bigint unless column_exists?(:live_streams, :actor_id)
    add_foreign_key :live_streams, :spree_users, column: :actor_id unless foreign_key_exists?(:live_streams, :spree_users, column: :actor_id)
  end
end