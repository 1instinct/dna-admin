module Spree::Api::V1::LiveStreamHelper
  def live_stream_detail(id)
    live_stream = LiveStream.find(id)
    live_stream = {
      id: live_stream&.id || 0,
      title: live_stream&.title || "",
      description: live_stream&.description || "",
      stream_url: live_stream&.stream_url || "",
      stream_key: live_stream&.stream_key || "",
      stream_id: live_stream&.stream_id || "",
      playback_ids: live_stream&.playback_ids || [],
      status: live_stream&.status || "",
      start_date: live_stream&.start_date || "",
      is_active: live_stream&.is_active || true,
      product_ids: live_stream&.product_ids || []
    }
    return live_stream
  end
end
