class CreateAdminThemes < ActiveRecord::Migration[6.1]
  def change
    create_table :admin_themes do |t|
      t.string  :brand_name,        default: 'Admin'
      t.string  :primary_color,     default: '#6366f1'
      t.string  :secondary_color,   default: '#8b5cf6'
      t.string  :surface_color,     default: '#1a1a2e'
      t.string  :background_color,  default: '#0f0f1a'
      t.string  :text_color,        default: '#e2e8f0'
      t.string  :sidebar_color,     default: '#16162a'
      t.string  :border_radius,     default: '8px'
      t.string  :font_family,       default: 'Inter, system-ui, sans-serif'
      t.string  :color_mode,        default: 'system'
      t.boolean :enable_animations, default: true
      t.text    :custom_css
      t.integer :singleton_guard,   default: 0, null: false
      t.timestamps
    end

    add_index :admin_themes, :singleton_guard, unique: true
  end
end
