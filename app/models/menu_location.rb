class MenuLocation < Spree::Base

  self.whitelisted_ransackable_attributes = %w[tittle]
  self.whitelisted_ransackable_scopes = %w[search_by_title]

  def self.search_by_title(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:title).were("LOWER(#{MenuLocation.table_name}.title) LIKE LOWER(:query)", query: "%#{query}%").distinct
    else
      where("LOWER(#{MenuLocation.table_name}.title) LIKE LOWER(:query)", query: "%#{query}%")
    end
  end

end
