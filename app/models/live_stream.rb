class LiveStream < Spree::Base
  has_many :live_stream_products, dependent: :destroy
  has_many :products, class_name: 'Spree::Product', through: :live_stream_products, dependent: :destroy
  belongs_to :thread_table, optional: :true
  belongs_to :actor, class_name: 'Spree::User'

  after_create :assign_thread_id
  self.whitelisted_ransackable_attributes = %w[title]
  self.whitelisted_ransackable_scopes = %w[search_livestream]

  def self.search_livestream(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:title).where("LOWER(#{LiveStream.table_name}.title) LIKE LOWER(:query) OR LOWER(description) LIKE LOWER(:query)", query: "%#{query}%").distinct
    else
      where("LOWER(#{LiveStream.table_name}.title) LIKE LOWER(:query) OR LOWER(description) LIKE LOWER(:query)", query: "%#{query}%")
    end
  end

  def assign_thread_id
    thread_table = ThreadTable.create(stale: true, archived: true)
    self.update(thread_table_id: thread_table.id)
  end
end
