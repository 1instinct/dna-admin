class Spree::Api::V1::MessagesController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:create, :update, :index, :destroy, :show]
  swagger_path "/messages/" do
    operation :post do
      key :summary, "Create Message"
      key :description, "Create Messages"
      key :tags, [
        'Messages'
      ]
      parameter do
        key :name, 'message[is_received]'
        key :in, :formData
        key :description, 'is_received'
        key :required, false
        key :type, :boolean
      end
      parameter do
        key :name, 'message[is_read]'
        key :in, :formData
        key :description, 'is_read'
        key :required, false
        key :type, :boolean
      end
      parameter do
        key :name, 'message[sentiment]'
        key :in, :formData
        key :description, 'sentiment'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'message[sender_type]'
        key :in, :formData
        key :description, 'sender_type. "Spree::User" or "Contact"'
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'message[sender_id]'
        key :in, :formData
        key :description, 'sender_id'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'message[receiver_type]'
        key :in, :formData
        key :description, 'receiver_type "Spree::User" or "Contact"'
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'message[receiver_id]'
        key :in, :formData
        key :description, 'receiver_id'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'message[message]'
        key :in, :formData
        key :description, "message"
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'message[thread_table_id]'
        key :in, :formData
        key :description, "thread_id"
        key :required, false
        key :type, :string
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :message_create_response
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
  swagger_schema :message_create_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :message
    end
  end
  swagger_schema :message do
    property :id do
      key :type, :integer
    end
    property :is_received do
      key :type, :boolean
    end
    property :is_read do
      key :type, :boolean
    end
    property :sentiment do
      key :type, :integer
    end
    property :sender_type do
      key :type, :string
    end
    property :sender_id do
      key :type, :integer
    end
    property :receiver_type do
      key :type, :string
    end
    property :receiver_id do
      key :type, :integer
    end
    property :thread_table_id do
      key :type, :integer
    end
    property :message do
      key :type, :string
    end
    property :created_at do
      key :type, :integer
      key :format, :int64
    end
    property :updated_at do
      key :type, :integer
      key :format, :int64
    end
  end

  def create
    message = Message.new(message_params)
    if message.save
      singular_success_model(200, Spree.t('message.success.create'), message_detail(message.id))
    else
      error_model(400, message.errors.full_messages.join(','))
      return
    end
  end

  swagger_path "/messages/{id}" do
    operation :patch do
      key :summary, "Update Message"
      key :description, "Update Messages"
      key :tags, [
        'Messages'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Message to fetch'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'message[is_received]'
        key :in, :formData
        key :description, 'is_received'
        key :required, false
        key :type, :boolean
      end
      parameter do
        key :name, 'message[is_read]'
        key :in, :formData
        key :description, 'is_read'
        key :required, false
        key :type, :boolean
      end
      parameter do
        key :name, 'message[sentiment]'
        key :in, :formData
        key :description, 'sentiment'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'message[sender_type]'
        key :in, :formData
        key :description, 'sender_type. "Spree::User" or "Contact"'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'message[sender_id]'
        key :in, :formData
        key :description, 'sender_id'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'message[receiver_type]'
        key :in, :formData
        key :description, 'receiver_type "Spree::User" or "Contact"'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'message[receiver_id]'
        key :in, :formData
        key :description, 'receiver_id'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'message[message]'
        key :in, :formData
        key :description, "message"
        key :required, false
        key :type, :string
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :message_update_response
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
  swagger_schema :message_update_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :message
    end
  end
  def update
    message = Message.find(params[:id])
    if message.update(message_params)
      singular_success_model(200, Spree.t('message.success.update'), message_detail(message.id))
    else
      error_model(400, message.errors.full_messages.join(','))
      return
    end
  end
  swagger_path "/messages/" do
    operation :get do
      key :summary, "List Messages"
      key :description, "List Messages"
      key :tags, [
        'Messages'
      ]
      parameter do
        key :name, 'search'
        key :in, :query
        key :description, 'Search String'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, :limit
        key :description, "limit"
        key :in, :query
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, :offset
        key :description, "offset"
        key :in, :query
        key :required, false
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :message_list_response
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
  swagger_schema :message_list_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      property :total_records do
        key :type, :integer
      end
      property :offset do
        key :type, :integer
      end
      property :message_listing do
        key :type, :array
        items do
          key :'$ref', :message
        end
      end
    end
  end
  def index
    message_listing = []
    query = params[:search]
    @messages = Message.all
    @messages = @messages.where("message ILIKE :query", query: "%#{query}%")&.distinct
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = @messages.count
    @messages = @messages.slice(offset, limit) unless limit == 0
    if @messages.present?
      @messages.each do |message|
        message_listing << message_detail(message.id)
      end
    end
    response_data = {
      total_records: total_count,
      offset: offset,
      message_listing: message_listing
    }
    singular_success_model(200, Spree.t('message.success.index'), response_data)
  end

  swagger_path "/messages/{id}" do
    operation :delete do
      key :summary, "Delete Message"
      key :description, "Delete Message"
      key :tags, [
        'Messages'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Message to fetch'
        key :required, true
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :common_response_model
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
  def destroy
    @message = Message.find(params[:id])
    if @message.destroy
      success_model(200, Spree.t('message.success.delete'))
    else
      error_model(400, @message.errors.full_messages.join(','))
    end
  end
  swagger_path "/messages/{id}" do
    operation :get do
      key :summary, "Show Message"
      key :description, "Show Message"
      key :tags, [
        'Messages'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Message to fetch'
        key :required, true
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :message_show_response
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
  swagger_schema :message_show_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :message
    end
  end
  def show
    @message = Message.find_by_id(params[:id])
    if @message.present?
      singular_success_model(200, Spree.t('message.success.show'), message_detail(@message.id))
    else
      error_model(400, Spree.t('message.error.not_found'))
    end
  end

  private
  def message_params
    params.require(:message).permit(:is_received, :is_read, :sentiment, :sender_type, :sender_id, :receiver_type, :receiver_id, :message, :thread_table_id)
  end
  def message_detail(id)
    message = Message.find(id)
    message = {
      id: message&.id || 0,
      is_received: message&.is_received || false,
      is_read: message&.is_read || false,
      sentiment: message&.sentiment || 0,
      created_at: to_timestamp(message&.created_at) || 0,
      updated_at: to_timestamp(message&.updated_at) || 0,
      sender_type: message&.sender_type || "",
      sender_id: message&.sender_id || 0,
      receiver_type: message&.receiver_type || "",
      receiver_id: message&.receiver_id || 0,
      thread_table_id: message&.thread_table_id || 0,
      message: message&.message || ""
    }
    return message
  end
end
