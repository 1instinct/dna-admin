module Spree::Api::V1::LiveStreamHelper
  include Spree::Api::V1::GlobalHelper
  def live_stream_detail(id)
    live_stream = LiveStream.find(id)
    live_stream = {
      id: live_stream&.id || 0,
      title: live_stream&.title || "",
      description: live_stream&.description || "",
      stream_url: live_stream&.stream_url || "",
      # The stream key lets anyone broadcast as this stream, and this payload is
      # public (a web proxy can serve it with a server key). Keep it out.
      stream_key: "",
      stream_id: live_stream&.stream_id || "",
      playback_ids: live_stream&.playback_ids || [],
      status: live_stream&.status || "",
      start_date: to_timestamp(live_stream&.start_date) || "",
      is_active: live_stream&.is_active || true,
      product_ids: visible_product_ids(live_stream),
      # Watchers are other people's contact records; not public.
      contact_ids: [],
      actor: user_detail(live_stream&.actor)
    }
    return live_stream
  end

  private

  def visible_product_ids(live_stream)
    return [] unless live_stream

    catalog_admin? ? live_stream.product_ids : live_stream.products.publicly_visible.ids
  end
end
