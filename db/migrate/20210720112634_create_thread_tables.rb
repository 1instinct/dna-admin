class CreateThreadTables < ActiveRecord::Migration[6.1]
  def change
    create_table :thread_tables do |t|
      t.boolean :archived
      t.boolean :stale

      t.timestamps
    end
  end
end
