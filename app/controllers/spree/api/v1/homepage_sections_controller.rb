class Spree::Api::V1::HomepageSectionsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  
  before_action :authenticate_user, except: [:index, :show]
  
  swagger_path "/homepage_sections" do
    operation :get do
      key :summary, "List Homepage Sections"
      key :description, "Returns all visible homepage sections ordered by position"
      key :tags, ['Homepage']
      
      parameter do
        key :name, :visible_only
        key :in, :query
        key :description, 'Filter to only visible sections (default: true)'
        key :required, false
        key :type, :boolean
      end
      
      response 200 do
        key :description, "Successful"
        schema do
          key :'$ref', :homepage_sections_response
        end
      end
    end
  end
  
  swagger_path "/homepage_sections/{id}" do
    operation :get do
      key :summary, "Get Homepage Section"
      key :description, "Returns a single homepage section by ID"
      key :tags, ['Homepage']
      
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'Section ID'
        key :required, true
        key :type, :integer
      end
      
      response 200 do
        key :description, "Successful"
        schema do
          key :'$ref', :homepage_section_response
        end
      end
      
      response 404 do
        key :description, "Not found"
      end
    end
  end
  
  swagger_schema :homepage_sections_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :type, :object
      property :total_records do
        key :type, :integer
      end
      property :offset do
        key :type, :integer
      end
      property :homepage_sections do
        key :type, :array
        items do
          key :'$ref', :homepage_section
        end
      end
    end
  end
  
  swagger_schema :homepage_section_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :homepage_section
    end
  end
  
  swagger_schema :homepage_section do
    property :id do
      key :type, :integer
    end
    property :title do
      key :type, :string
    end
    property :section_type do
      key :type, :string
    end
    property :content do
      key :type, :string
    end
    property :position do
      key :type, :integer
    end
    property :is_visible do
      key :type, :boolean
    end
    property :settings do
      key :type, :object
    end
    property :created_at do
      key :type, :string
      key :format, 'date-time'
    end
    property :updated_at do
      key :type, :string
      key :format, 'date-time'
    end
  end
  
  def index
    visible_only = params[:visible_only].nil? ? true : params[:visible_only] == 'true'
    
    @sections = visible_only ? HomepageSection.visible : HomepageSection.all
    @sections = @sections.order(position: :asc)
    
    count = @sections.count
    offset = params[:offset].to_i
    
    render_object_success(@sections, "Homepage sections retrieved successfully", :homepage_sections, count, offset)
  end
  
  def show
    @section = HomepageSection.find_by(id: params[:id])
    
    if @section
      singular_success_model(200, "Homepage section retrieved successfully", section_data(@section))
    else
      error_model(404, "Homepage section not found")
    end
  end
  
  def create
    @section = HomepageSection.new(homepage_section_params)
    
    if @section.save
      singular_success_model(201, "Homepage section created successfully", section_data(@section))
    else
      error_model(400, @section.errors.full_messages.join(', '))
    end
  end
  
  def update
    @section = HomepageSection.find_by(id: params[:id])
    
    if @section.nil?
      error_model(404, "Homepage section not found")
    elsif @section.update(homepage_section_params)
      singular_success_model(200, "Homepage section updated successfully", section_data(@section))
    else
      error_model(400, @section.errors.full_messages.join(', '))
    end
  end
  
  def destroy
    @section = HomepageSection.find_by(id: params[:id])
    
    if @section.nil?
      error_model(404, "Homepage section not found")
    elsif @section.destroy
      success_model(200, "Homepage section deleted successfully")
    else
      error_model(400, "Failed to delete homepage section")
    end
  end
  
  private
  
  def homepage_section_params
    params.require(:homepage_section).permit(
      :title,
      :section_type,
      :content,
      :position,
      :is_visible,
      settings: {}
    )
  end
  
  def section_data(section)
    {
      id: section.id,
      title: section.title,
      section_type: section.section_type,
      content: section.content,
      position: section.position,
      is_visible: section.is_visible,
      settings: section.settings,
      created_at: section.created_at,
      updated_at: section.updated_at
    }
  end
end
