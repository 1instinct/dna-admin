class CreateContentAssets < ActiveRecord::Migration[6.1]
  def change
    create_table :content_assets do |t|
      t.string  :alt_text,          limit: 255
      t.string  :tag,               limit: 100
      t.string  :original_filename, null: false, default: ''
      t.string  :content_type,      null: false, default: ''
      t.integer :byte_size,         null: false, default: 0
      t.timestamps
    end

    add_index :content_assets, :tag
    add_index :content_assets, :created_at
  end
end
