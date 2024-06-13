class Spree::Api::V1::MenuItemsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:index, :show]
  
  swagger_path "/menu_items/" do
    operation :get do
      key :summary, "List Menu items"
      key :description, "List Menu items"
      key :tags, [
        'Menu Item'
      ]
      parameter do
        key :name, 'menu_location_id'
        key :in, :query
        key :description, 'fetch  menu items according to menu location'
        key :required, false
        key :type, :integer
      end
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
          key :'$ref', :menu_item_list_response
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
  swagger_schema :menu_item_list_response do
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
          key :'$ref', :menu_location_with_menu_items
        end
      end
    end
  end
  swagger_schema :menu_location_with_menu_items do
    property :id do
      key :type, :integer
    end
    property :title do
      key :type, :string
    end
    property :menu_item_listing do
      key :type, :array
      items do
        key :'$ref', :menu_item
      end
    end
  end

  def index
    menu_location_listing = []
    menu_item_listing = []
    query = params[:search]
    menu_locations = MenuLocation.all
    @menu_item = MenuItem.all
    menu_locations = menu_locations.where(id: params[:menu_location_id]) if params[:menu_location_id].present?
    menu_locations = menu_locations.where("title ILIKE :query", query: "%#{query}%")&.distinct
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = menu_locations.count
    @menu_item = menu_locations.slice(offset, limit) unless limit == 0
    menu_locations.each do |menu_location|
      menu_location.menu_items.each do |menu_item|
        menu_item_listing << menu_item_detail(menu_item.id)
      end
      menu_location_listing << {
        id: menu_location&.id || 0,
        title: menu_location&.title || "",
        menu_item_listing: menu_item_listing
      }
    end
    response_data = {
      total_records: total_count,
      offset: offset,
      menu_location_listing: menu_location_listing
    }
    singular_success_model(200, Spree.t('menu_item.success.index'), response_data)
  end

  swagger_path "/menu_items/{id}" do
    operation :get do
      key :summary, "Show Menu Item"
      key :description, "Show Menu Item"
      key :tags, [
        'Menu Item'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Menu Item to fetch'
        key :required, true
        key :type, :integer
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_item_show_response
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
  swagger_schema :menu_item_show_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :menu_item
    end
  end
  def show
    @menu_item = MenuItem.find_by_id(params[:id])
    if @menu_item.present?
      singular_success_model(200, Spree.t('menu_item.success.show'), menu_item_detail(@menu_item.id))
    else
      error_model(400, Spree.t('menu_item.error.not_found'))
    end
  end

  private
  def menu_item_params
    params.require(:menu_item).permit(:name, :url, :item_class, :item_id, :item_target, :parent_id, :position, :is_visible)
  end
  def menu_item_detail(id)
    menu_item = MenuItem.find(id)
    childrens = []
    @fetch_childrens = fetch_childrens(menu_item)
    @fetch_childrens = @fetch_childrens.where(parent_id: menu_item.id)
    @fetch_childrens.each do |mi|
      childrens << menu_item_detail(mi.id)
    end
    menu_item = {
      id: menu_item&.id || 0,
      name: menu_item&.name || "",
      url: menu_item&.url || "",
      item_class: menu_item&.item_class || "",
      item_id: menu_item&.item_id || "",
      item_target: menu_item&.item_target || "",
      parent_id: menu_item&.parent_id || 0,
      position: menu_item&.position || 0,
      is_visible: menu_item&.is_visible || false,
      created_at: to_timestamp(menu_item&.created_at) || 0,
      updated_at: to_timestamp(menu_item&.updated_at) || 0,
      childrens: childrens || []
    }
    return menu_item
  end
  def fetch_childrens(menu_item)
    childrens = MenuItem.all.where(id: menu_item.child_chain.pluck(:id))
    return childrens
  end
end
