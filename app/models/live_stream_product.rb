class LiveStreamProduct < ApplicationRecord
  belongs_to :live_stream
  belongs_to :product
end
