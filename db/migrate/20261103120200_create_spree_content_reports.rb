class CreateSpreeContentReports < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_content_reports do |t|
      t.integer :reporter_id
      t.string :reportable_type, null: false
      t.bigint :reportable_id, null: false
      t.string :reason, null: false
      t.text :details
      t.jsonb :snapshot, null: false, default: {}
      t.string :status, null: false, default: 'open'
      t.integer :resolved_by_id
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end

    add_index :spree_content_reports, %i[reportable_type reportable_id], name: 'index_spree_content_reports_on_reportable'
    add_index :spree_content_reports, %i[reporter_id created_at]
    add_index :spree_content_reports, %i[status created_at]
    add_foreign_key :spree_content_reports, :spree_users, column: :reporter_id, on_delete: :nullify
    add_foreign_key :spree_content_reports, :spree_users, column: :resolved_by_id, on_delete: :nullify
  end
end
