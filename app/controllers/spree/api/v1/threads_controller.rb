class Spree::Api::V1::ThreadsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:index, :destroy, :show]

  swagger_path "/threads/" do
    operation :get do
      key :summary, "List Threads"
      key :description, "List Threads"
      key :tags, [
        'Threads'
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
          key :'$ref', :thread_list_response
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
  swagger_schema :thread_list_response do
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
      property :thread_listing do
        key :type, :array
        items do
          key :'$ref', :thread
        end
      end
    end
  end
  swagger_schema :thread do
    property :id do
      key :type, :integer
    end
    property :archived do
      key :type, :boolean
    end
    property :stale do
      key :type, :boolean
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
  def index
    thread_listing = []
    query = params[:search]
    threads = ThreadTable.all
    if params[:search].present?
      threads = threads.where("id ILIKE :query", query: "%#{query}%")&.distinct
    end
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = threads.count
    threads = threads.slice(offset, limit) unless limit == 0
    if threads.present?
      threads.each do |thread|
        thread_listing << thread_detail(thread.id)
      end
    end
    response_data = {
      total_records: total_count,
      offset: offset,
      thread_listing: thread_listing
    }
    singular_success_model(200, Spree.t('thread.success.index'), response_data)
  end

  swagger_path "/threads/{id}" do
    operation :delete do
      key :summary, "Delete Thread"
      key :description, "Delete Thread"
      key :tags, [
        'Threads'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Thread to fetch'
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
    @thread = ThreadTable.find_by_id(params[:id])
    unless @thread.present?
      error_model(400, Spree.t('thread.error.not_found'))
      return
    end
    if @thread.destroy
      success_model(200, Spree.t('thread.success.delete'))
    else
      error_model(400, @thread.errors.full_messages.join(','))
    end
  end
  swagger_path "/threads/{id}" do
    operation :get do
      key :summary, "Show Thread"
      key :description, "Show Thread"
      key :tags, [
        'Threads'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Thread to fetch'
        key :required, true
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :thread_show_response
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
  swagger_schema :thread_show_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :thread
    end
  end
  def show
    @thread = ThreadTable.find_by_id(params[:id])
    if @thread.present?
      singular_success_model(200, Spree.t('thread.success.show'), thread_detail(@thread.id))
    else
      error_model(400, Spree.t('thread.error.not_found'))
    end
  end

  private
  def thread_detail(id)
    thread = ThreadTable.find(id)
    thread = {
      id: thread&.id || 0,
      archived: thread&.archived || true,
      stale: thread&.stale || "",
      created_at: to_timestamp(thread&.created_at) || 0,
      updated_at: to_timestamp(thread&.updated_at) || 0
    }
    return thread
  end
end
