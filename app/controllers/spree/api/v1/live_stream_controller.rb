module Spree::Api::V1
  class LiveStreamController < Spree::Api::BaseController
    include Swagger::Blocks
    include Response
    include Spree::Api::V1::LiveStreamHelper

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
      property :product_ids do
        key :type, :array
        items do
          key :type, :string
        end
      end
    end

    def index
      live_streams = []
      @live_streams = LiveStream.all
      @live_streams.each do |live_stream|
        live_streams << live_stream_detail(live_stream.id)
      end
      singular_success_model(200, Spree.t('live_stream.list_success'), live_streams)
    end
    swagger_path "/live_stream/{id}" do
      operation :get do
        key :summary, "Fetch Live Stream"
        key :description, "Fetch Live Stream"
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
        parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of live stream to fetch'
            key :required, true
            key :type, :integer
          end
        response 200 do
          key :description, "Successfull"
          schema do
            key :'$ref', :single_live_stream_response
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
    swagger_schema :single_live_stream_response do
      key :required, [:response_code, :response_message]
      property :response_code do
        key :type, :integer
      end
      property :response_message do
        key :type, :string
      end
      property :response_data do
        key :'$ref', :live_stream
      end
    end
    def show
      live_stream = LiveStream.find(params[:id])
      if live_stream.present?
        singular_success_model(200, "Live Stream fetch successfully.", live_stream_detail(live_stream.id))
      else
        error_model(400, "Live Stream not found.")
      end
    end
  end
end
