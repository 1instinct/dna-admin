class ChangeHomepageSectionPositionDefault < ActiveRecord::Migration[6.1]
  def up
    # Remove the default value of 0
    change_column_default :homepage_sections, :position, from: 0, to: nil
    
    # Reset positions for existing records
    execute <<-SQL
      UPDATE homepage_sections
      SET position = subquery.new_position
      FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) as new_position
        FROM homepage_sections
      ) AS subquery
      WHERE homepage_sections.id = subquery.id;
    SQL
  end
  
  def down
    change_column_default :homepage_sections, :position, from: nil, to: 0
  end
end
