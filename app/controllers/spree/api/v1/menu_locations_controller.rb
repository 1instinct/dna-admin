class Spree::Api::V1::MenuLocationsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:create, :update, :index, :destroy, :show]
  swagger_path "/menu_locations/" do
    operation :post do
      key :summary, "Create Menu Location"
      key :description, "Create Menu Location"
      key :tags, [
        'Menu Location'
      ]
      parameter do
        key :name, 'menu_location[title]'
        key :in, :formData
        key :description, 'title'
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'menu_location[location]'
        key :in, :formData
        key :description, 'location'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_location[is_visible]'
        key :in, :formData
        key :description, 'is_visible'
        key :required, false
        key :type, :boolean
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_location_create_response
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
  swagger_schema :menu_location_create_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :menu_location
    end
  end
  swagger_schema :menu_location do
    property :id do
      key :type, :integer
    end
    property :title do
      key :type, :string
    end
    property :location do
      key :type, :string
    end
    property :is_visible do
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

  def create
    menu_location = MenuLocation.new(menu_location_params)
    if menu_location.save
      singular_success_model(200, Spree.t('menu_location.success.create'), menu_location_detail(menu_location.id))
    else
      error_model(400, menu_location.errors.full_messages.join(','))
      return
    end
  end

  swagger_path "/menu_locations/{id}" do
    operation :patch do
      key :summary, "Update Menu location"
      key :description, "Update Menu location"
      key :tags, [
        'Menu Location'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Menu Location to fetch'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'menu_location[title]'
        key :in, :formData
        key :description, 'title'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_location[location]'
        key :in, :formData
        key :description, 'location'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_location[is_visible]'
        key :in, :formData
        key :description, 'is_visible'
        key :required, false
        key :type, :boolean
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_location_update_response
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
  swagger_schema :menu_location_update_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :menu_location
    end
  end
  def update
    menu_location = MenuLocation.find_by_id(params[:id])
    unless menu_location.present?
      error_model(400, "menu_location not found")
      return
    end
    if menu_location.update(menu_location_params)
      singular_success_model(200, Spree.t('menu_location.success.update'), menu_location_detail(menu_location.id))
    else
      error_model(400, menu_location.errors.full_messages.join(','))
      return
    end
  end
  swagger_path "/menu_locations/" do
    operation :get do
      key :summary, "List Menu Locations"
      key :description, "List Menu Locations"
      key :tags, [
        'Menu Location'
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
          key :'$ref', :menu_location_list_response
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
  swagger_schema :menu_location_list_response do
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
      property :menu_location_listing do
        key :type, :array
        items do
          key :'$ref', :menu_location
        end
      end
    end
  end
  def index
    menu_location_listing = []
    query = params[:search]
    @menu_location = MenuLocation.all
    @menu_location = @menu_location.where("title ILIKE :query", query: "%#{query}%")&.distinct
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = @menu_location.count
    @menu_location = @menu_location.slice(offset, limit) unless limit == 0
    if @menu_location.present?
      @menu_location.each do |menu_location|
        menu_location_listing << menu_location_detail(menu_location.id)
      end
    end
    response_data = {
      total_records: total_count,
      offset: offset,
      menu_location_listing: menu_location_listing
    }
    singular_success_model(200, Spree.t('menu_location.success.index'), response_data)
  end

  swagger_path "/menu_locations/{id}" do
    operation :delete do
      key :summary, "Delete Menu Location"
      key :description, "Delete Menu Location"
      key :tags, [
        'Menu Location'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Menu Location to fetch'
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
    @menu_location = MenuLocation.find_by_id(params[:id])
    unless @menu_location.present?
      error_model(400, "menu_location not found")
      return
    end
    if @menu_location.destroy
      success_model(200, Spree.t('menu_location.success.delete'))
    else
      error_model(400, @menu_location.errors.full_messages.join(','))
    end
  end
  swagger_path "/menu_locations/{id}" do
    operation :get do
      key :summary, "Show Menu Location"
      key :description, "Show Menu Location"
      key :tags, [
        'Menu Location'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Menu Location to fetch'
        key :required, true
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_location_show_response
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
  swagger_schema :menu_location_show_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :menu_location
    end
  end
  def show
    @menu_location = MenuLocation.find_by_id(params[:id])
    if @menu_location.present?
      singular_success_model(200, Spree.t('menu_location.success.show'), menu_location_detail(@menu_location.id))
    else
      error_model(400, Spree.t('menu_location.error.not_found'))
    end
  end

  private
  def menu_location_params
    params.require(:menu_location).permit(:title, :location, :is_visible)
  end
  def menu_location_detail(id)
    menu_location = MenuLocation.find(id)
    menu_location = {
      id: menu_location&.id || 0,
      title: menu_location&.title || "",
      location: menu_location&.location || "",
      is_visible: menu_location&.is_visible || false,
      created_at: to_timestamp(menu_location&.created_at) || 0,
      updated_at: to_timestamp(menu_location&.updated_at) || 0
    }
    return menu_location
  end
end
