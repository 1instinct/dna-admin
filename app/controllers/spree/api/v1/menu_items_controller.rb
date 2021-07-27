class Spree::Api::V1::MenuItemsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:create, :update, :index, :destroy, :show]
  swagger_path "/menu_items/" do
    operation :post do
      key :summary, "Create Menu Item"
      key :description, "Create Menu Item"
      key :tags, [
        'Menu Item'
      ]
      parameter do
        key :name, 'menu_item[name]'
        key :in, :formData
        key :description, 'name'
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[url]'
        key :in, :formData
        key :description, 'url'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_class]'
        key :in, :formData
        key :description, 'item_class'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_id]'
        key :in, :formData
        key :description, 'item_id'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_target]'
        key :in, :formData
        key :description, 'item_target'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[parent_id]'
        key :in, :formData
        key :description, 'parent_id'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'menu_item[position]'
        key :in, :formData
        key :description, 'position'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'menu_item[is_visible]'
        key :in, :formData
        key :description, 'is_visible'
        key :required, false
        key :type, :boolean
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_item_create_response
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
  swagger_schema :menu_item_create_response do
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
  swagger_schema :menu_item do
    property :id do
      key :type, :integer
    end
    property :name do
      key :type, :string
    end
    property :url do
      key :type, :string
    end
    property :item_class do
      key :type, :string
    end
    property :item_id do
      key :type, :string
    end
    property :item_target do
      key :type, :string
    end
    property :parent_id do
      key :type, :integer
    end
    property :position do
      key :type, :integer
    end
    property :created_at do
      key :type, :integer
      key :format, :int64
    end
    property :updated_at do
      key :type, :integer
      key :format, :int64
    end
    property :is_visible do
      key :type, :boolean
    end
  end

  def create
    menu_item = MenuItem.new(menu_item_params)
    if menu_item.save
      singular_success_model(200, Spree.t('menu_item.success.create'), menu_item_detail(menu_item.id))
    else
      error_model(400, menu_item.errors.full_messages.join(','))
      return
    end
  end

  swagger_path "/menu_items/{id}" do
    operation :patch do
      key :summary, "Update Menu item"
      key :description, "Update Menu item"
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
      parameter do
        key :name, 'menu_item[name]'
        key :in, :formData
        key :description, 'name'
        key :required, true
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[url]'
        key :in, :formData
        key :description, 'url'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_class]'
        key :in, :formData
        key :description, 'item_class'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_id]'
        key :in, :formData
        key :description, 'item_id'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[item_target]'
        key :in, :formData
        key :description, 'item_target'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'menu_item[parent_id]'
        key :in, :formData
        key :description, 'parent_id'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'menu_item[position]'
        key :in, :formData
        key :description, 'position'
        key :required, false
        key :type, :integer
      end
      parameter do
        key :name, 'menu_item[is_visible]'
        key :in, :formData
        key :description, 'is_visible'
        key :required, false
        key :type, :boolean
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :menu_item_update_response
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
  swagger_schema :menu_item_update_response do
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
  def update
    menu_item = MenuItem.find_by_id(params[:id])
    unless menu_item.present?
      error_model(400, "Menu Item not found.")
      return
    end
    if menu_item.update(menu_item_params)
      singular_success_model(200, Spree.t('menu_item.success.update'), menu_item_detail(menu_item.id))
    else
      error_model(400, menu_item.errors.full_messages.join(','))
      return
    end
  end
  swagger_path "/menu_items/" do
    operation :get do
      key :summary, "List Menu items"
      key :description, "List Menu items"
      key :tags, [
        'Menu Item'
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
      property :menu_item_listing do
        key :type, :array
        items do
          key :'$ref', :menu_item
        end
      end
    end
  end
  def index
    menu_item_listing = []
    query = params[:search]
    @menu_item = MenuItem.all
    @menu_item = @menu_item.where("name ILIKE :query", query: "%#{query}%")&.distinct
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = @menu_item.count
    @menu_item = @menu_item.slice(offset, limit) unless limit == 0
    if @menu_item.present?
      @menu_item.each do |menu_item|
        menu_item_listing << menu_item_detail(menu_item.id)
      end
    end
    response_data = {
      total_records: total_count,
      offset: offset,
      menu_item_listing: menu_item_listing
    }
    singular_success_model(200, Spree.t('menu_item.success.index'), response_data)
  end

  swagger_path "/menu_items/{id}" do
    operation :delete do
      key :summary, "Delete Menu Item"
      key :description, "Delete Menu Item"
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
    @menu_item = MenuItem.find_by_id(params[:id])
    unless @menu_item.present?
      error_model(400, "Menu Item not found")
      return
    end
    if @menu_item.destroy
      success_model(200, Spree.t('menu_item.success.delete'))
    else
      error_model(400, @menu_item.errors.full_messages.join(','))
    end
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
      updated_at: to_timestamp(menu_item&.updated_at) || 0
    }
    return menu_item
  end
end
