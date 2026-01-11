class CreateHomepageSections < ActiveRecord::Migration[6.1]
  def change
    create_table :homepage_sections do |t|
      t.string :title, null: false
      t.string :section_type, null: false # hero, features, products, content, testimonials, etc.
      t.text :content
      t.integer :position, default: 0, null: false
      t.boolean :is_visible, default: true
      t.json :settings # flexible JSON for section-specific settings

      t.timestamps
    end
    
    add_index :homepage_sections, :position
    add_index :homepage_sections, :is_visible
    add_index :homepage_sections, :section_type
  end
end
