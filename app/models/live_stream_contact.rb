class LiveStreamContact < ApplicationRecord
  belongs_to :live_stream
  belongs_to :contact
end
