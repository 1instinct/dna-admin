class SwaggerGlobalModel  # Notice, this is just a plain ruby object.
  include Swagger::Blocks

  swagger_schema :common_response_model do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
      key :format, :int32
    end
    property :response_message do
      key :type, :string
    end
  end

  swagger_schema :favorites_list_response do
    key :required, [:status, :message, :data]
    property :status do
      key :type, :integer
    end
    property :message do
      key :type, :string
    end
    property :data do
      key :type, :array
      items do
        key :'$ref', :favorite_object
      end
    end
    property :meta do
      key :'$ref', :pagination_meta
    end
  end

  swagger_schema :favorite_toggle_response do
    key :required, [:status, :message]
    property :status do
      key :type, :integer
    end
    property :message do
      key :type, :string
    end
  end

  swagger_schema :favorite_object do
    property :id do
      key :type, :integer
    end
    property :created_at do
      key :type, :string
      key :format, 'date-time'
    end
    property :variant do
      key :type, :object
      property :id do
        key :type, :integer
      end
      property :sku do
        key :type, :string
      end
      property :name do
        key :type, :string
      end
      property :price do
        key :type, :string
      end
      property :in_stock do
        key :type, :boolean
      end
      property :product do
        key :type, :object
        property :id do
          key :type, :integer
        end
        property :name do
          key :type, :string
        end
        property :slug do
          key :type, :string
        end
        property :description do
          key :type, :string
        end
        property :images do
          key :type, :array
          items do
            key :type, :object
            property :url do
              key :type, :string
            end
          end
        end
      end
    end
  end

  swagger_schema :pagination_meta do
    property :total_count do
      key :type, :integer
    end
    property :current_page do
      key :type, :integer
    end
    property :total_pages do
      key :type, :integer
    end
    property :per_page do
      key :type, :integer
    end
  end

end

