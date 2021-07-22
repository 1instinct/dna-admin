class LiveStream < ApplicationRecord
  has_many :live_stream_products, dependent: :destroy
  has_many :products, class_name: 'Spree::Product', through: :live_stream_products, dependent: :destroy
  belongs_to :thread, class_name: "ThreadTable", optional: :true

  after_create :assign_thread_id
  def assign_thread_id
    thread_table = ThreadTable.create(stale: true, archived: true)
    self.update(thread_table_id: thread_table.id)
  end
end
