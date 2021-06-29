class LiveStream < ApplicationRecord
  belongs_to :user
  belongs_to :live_stream
end
