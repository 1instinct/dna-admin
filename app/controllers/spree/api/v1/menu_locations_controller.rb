class Spree::Api::V1::MenuLocationsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:index, :show]

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
