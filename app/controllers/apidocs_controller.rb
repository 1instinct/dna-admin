class ApidocsController < ActionController::Base
  include Swagger::Blocks
  swagger_root do
    key :swagger, '2.0'
    info do
      key :version, '1.0.0'
      key :title, ENV['SITE_TITLE']
      key :description, ENV['SITE_DESCRIPTION']
      contact do
        key :name, ENV['SITE_ADMIN_NAME']
      end
    end
    key :host, 'http://localhost:8080/apidocs.json' if Rails.env.development?
    key :host, 'https://dna-admin-staging.instinct.is/' if Rails.env.staging?
    key :host, 'https://admin.instinct.is/' if Rails.env.production?


    key :basePath, '/api/v1'
    key :consumes, ['application/x-www-form-urlencoded'] #this means what responce we are going to send
    key :produces, ['application/json'] # and this means what type of responce we are going to get from user
  end

  # A list of all classes that have swagger_* declarations.
  SWAGGERED_CLASSES_V1 = [
    #SwaggerController, #controller details goes from here where from you are creating api
    Spree::Api::V1::LiveStreamController,
    Spree::Api::V1::UsersController,
    Spree::Api::V1::PagesController,
<<<<<<< HEAD
    Spree::Api::V1::ContactsController,
    Spree::Api::V1::MessagesController,
    Spree::Api::V1::ThreadsController,
    Spree::Api::V1::MenuLocationsController,
    Spree::Api::V1::MenuItemsController,
=======
    Spree::Api::V1::MenuLocationsController,
>>>>>>> e68314f (add menu location to swagger)
    SwaggerGlobalModel,
    self,
  ].freeze

  def index
    render json: Swagger::Blocks.build_root_json(SWAGGERED_CLASSES_V1)
  end

  def swagger_ui
  end
end
