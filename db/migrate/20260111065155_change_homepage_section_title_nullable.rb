class ChangeHomepageSectionTitleNullable < ActiveRecord::Migration[6.1]
  def change
    change_column_null :homepage_sections, :title, true
  end
end
