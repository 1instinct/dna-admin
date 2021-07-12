class Spree::Api::V1::PagesController < ApplicationController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  swagger_path "/pages" do
    operation :get do
      key :summary, "Pages Listing and Searching."
      key :description, "Pages Listing and Searching."
      key :tags, [
        'Pages'
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
          key :'$ref', :page_search_response
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
  swagger_schema :page_search_response do
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
      property :page_listing do
        key :type, :array
        items do
          key :'$ref', :page
        end
      end
    end
  end
  swagger_schema :page do
    property :id do
      key :type, :integer
    end
    property :title do
      key :type, :string
    end
    property :body do
      key :type, :string
    end
    property :slug do
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
    property :show_in_header do
      key :type, :boolean
    end
    property :foreign_link do
      key :type, :string
    end
    property :position do
      key :type, :integer
    end
    property :visible do
      key :type, :boolean
    end
    property :meta_keywords do
      key :type, :string
    end
    property :meta_description do
      key :type, :string
    end
    property :layout do
      key :type, :string
    end
    property :show_in_sidebar do
      key :type, :boolean
    end
    property :meta_title do
      key :type, :string
    end
    property :render_layout_as_partial do
      key :type, :boolean
    end
    property :show_in_footer do
      key :type, :boolean
    end
  end
  def index
    page_listing = []
    query = params[:search]
    pages = Spree::Page.all
    pages = pages.where("title ILIKE :query OR body ILIKE :query", query: "%#{query}%")&.distinct
    limit = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    total_count = pages.count
    pages = pages.slice(offset, limit) unless limit == 0
    pages&.each do |page|
      page_listing << {
        id: page&.id || 0,
        title: page&.title || "",
        body: page&.body || "",
        slug: page&.slug || "",
        created_at: to_timestamp(page&.created_at) || 0,
        updated_at: to_timestamp(page&.updated_at) || 0,
        show_in_header: page&.show_in_header || false,
        foreign_link: page&.foreign_link || "",
        position: page&.position || 0,
        visible: page&.visible || false,
        meta_keywords: page&.meta_keywords || "",
        meta_description: page&.meta_description || "",
        layout: page&.layout || "",
        show_in_sidebar: page&.show_in_sidebar || false,
        meta_title: page&.meta_title || "",
        render_layout_as_partial: page&.render_layout_as_partial || false,
        show_in_footer: page&.show_in_footer || false
      }
    end

    response_data = {
      total_records: total_count,
      offset: offset,
      page_listing: page_listing
    }
    singular_success_model(200, Spree.t('page.success.page_list'), response_data)
  end
  swagger_path "/pages/{slug}" do
    operation :get do
      key :summary, "Fetch page using slug"
      key :description, "Fetch page using slug"
      key :tags, [
        'Pages'
      ]
      parameter do
        key :name, :slug
        key :in, :path
        key :description, 'slug of page to fetch'
        key :required, true
        key :type, :string
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :single_page_response
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
  swagger_schema :single_page_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :page
    end
  end
  def show
    page = Spree::Page.find_by_slug(params[:slug])
    if page.present?
      response_data = {
        id: page&.id || 0,
        title: page&.title || "",
        body: page&.body || "",
        slug: page&.slug || "",
        created_at: to_timestamp(page&.created_at) || 0,
        updated_at: to_timestamp(page&.updated_at) || 0,
        show_in_header: page&.show_in_header || false,
        foreign_link: page&.foreign_link || "",
        position: page&.position || 0,
        visible: page&.visible || false,
        meta_keywords: page&.meta_keywords || "",
        meta_description: page&.meta_description || "",
        layout: page&.layout || "",
        show_in_sidebar: page&.show_in_sidebar || false,
        meta_title: page&.meta_title || "",
        render_layout_as_partial: page&.render_layout_as_partial || false,
        show_in_footer: page&.show_in_footer || false
      }
      singular_success_model(200, Spree.t('page.success.show'), response_data)
    else
      error_model(400, Spree.t('page.error.page_not_found'))
    end
  end
end
