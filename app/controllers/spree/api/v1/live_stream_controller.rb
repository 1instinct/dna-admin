module Spree::Api::V1
  class LiveStreamController < Spree::Api::BaseController
    include Swagger::Blocks
    include Response

    swagger_path "/live_stream" do
      operation :get do
        key :summary, "List Live Stream"
        key :description, "List Live Stream"
        key :tags, [
          'LiveStream'
        ]
        parameter do
          key :name, :'X-Spree-Token'
          key :description, "User API Key"
          key :type, :string
          key :in, :header
          key :required, true
        end
        response 200 do
          key :description, "Successfull"
          schema do
            key :'$ref', :live_stream_response
          end
        end
        response 400 do
          key :description, "Error"
          schema do
            key :'$ref', :common_response_model
          end
        end
      end
    end
    swagger_schema :live_stream_response do
      key :required, [:response_code, :response_message]
      property :response_code do
        key :type, :integer
      end
      property :response_message do
        key :type, :string
      end
      property :response_data do
        key :type, :array
        items do
          key :'$ref', :live_stream
        end
      end
    end
    swagger_schema :live_stream do
      property :id do
        key :type, :integer
      end
      property :title do
        key :type, :string
      end
      property :description do
        key :type, :string
      end
      property :stream_url do
        key :type, :string
      end
      property :stream_key do
        key :type, :string
      end
      property :stream_id do
        key :type, :string
      end
      property :playback_ids do
        key :type, :array
        items do
          key :type, :string
        end
      end
      property :status do
        key :type, :string
      end
      property :start_date do
        key :type, :string
      end
      property :is_active do
        key :type, :boolean
      end
    end

    def index
      live_streams = []
      @live_streams = LiveStream.all
      @live_streams.each do |live_stream|
        live_streams << {
          id: live_stream&.id || 0,
          title: live_stream&.title || "",
          description: live_stream&.description || "",
          stream_url: live_stream&.stream_url || "",
          stream_key: live_stream&.stream_key || "",
          stream_id: live_stream&.stream_id || "",
          playback_ids: live_stream&.playback_ids || [],
          status: live_stream&.status || "",
          start_date: live_stream&.start_date || "",
          is_active: live_stream&.is_active || true
        }
      end
      singular_success_model(200, Spree.t('live_stream.list_success'), live_streams)
    end
  end
end
