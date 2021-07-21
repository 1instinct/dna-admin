class Spree::Api::V1::ContactsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:create, :update, :index]
  swagger_path "/contacts/" do
    operation :post do
      key :summary, "Create Contact"
      key :description, "Create Contacts"
      key :tags, [
        'Contacts'
      ]
      parameter do
        key :name, 'contact[actor_id]'
        key :in, :formData
        key :description, 'actor_id'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'contact[full_name]'
        key :in, :formData
        key :description, 'full_name'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[email]'
        key :in, :formData
        key :description, "emails comma separated exa. abc@gmail.com, xyz@gmail.com"
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[phone]'
        key :in, :formData
        key :description, "phones numbers exa. 12345678,87654321"
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[ip]'
        key :in, :formData
        key :description, 'IP address'
        key :required, false
        key :type, :string
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :contact_create_response
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
  swagger_schema :contact_create_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :contact
    end
  end
  swagger_schema :contact do
    property :id do
      key :type, :integer
    end
    property :actor_id do
      key :type, :integer
    end
    property :full_name do
      key :type, :string
    end
    property :email do
      key :type, :array
      items do
        key :type, :string
      end
    end
    property :phone do
      key :type, :array
      items do
        key :type, :string
      end
    end
    property :ip do
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
    contact = Contact.new(contact_params)
    if contact.save
      singular_success_model(200, Spree.t('contact.success.create'), contact_detail(contact.id))
    else
      error_model(400, contact.errors.full_messages.join(','))
      return
    end
  end

  swagger_path "/contacts/{id}" do
    operation :patch do
      key :summary, "Update Contact"
      key :description, "Update Contacts"
      key :tags, [
        'Contacts'
      ]
      parameter do
        key :name, :id
        key :in, :path
        key :description, 'ID of Contact to fetch'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'contact[actor_id]'
        key :in, :formData
        key :description, 'actor_id'
        key :required, true
        key :type, :integer
      end
      parameter do
        key :name, 'contact[full_name]'
        key :in, :formData
        key :description, 'full_name'
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[email]'
        key :in, :formData
        key :description, "emails comma separated exa. abc@gmail.com, xyz@gmail.com"
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[phone]'
        key :in, :formData
        key :description, "phones numbers exa. 12345678,87654321"
        key :required, false
        key :type, :string
      end
      parameter do
        key :name, 'contact[ip]'
        key :in, :formData
        key :description, 'IP address'
        key :required, false
        key :type, :string
      end
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :contact_update_response
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
  swagger_schema :contact_update_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :'$ref', :contact
    end
  end
  def update
    contact = Contact.find(params[:id])
    if contact.update(contact_params)
      singular_success_model(200, Spree.t('contact.success.update'), contact_detail(contact.id))
    else
      error_model(400, contact.errors.full_messages.join(','))
      return
    end
  end
  swagger_path "/contacts/" do
    operation :get do
      key :summary, "List Contacts"
      key :description, "List Contacts"
      key :tags, [
        'Contacts'
      ]
      response 200 do
        key :description, "Successfull"
        schema do
          key :'$ref', :contact_list_response
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
  swagger_schema :contact_list_response do
    key :required, [:response_code, :response_message]
    property :response_code do
      key :type, :integer
    end
    property :response_message do
      key :type, :string
    end
    property :response_data do
      key :type, :array
      items do
        key :'$ref', :contact
      end
    end
  end
  def index
    contacts = []
    @contacts = Contact.all
    @contacts.each do |contact|
      contacts << contact_detail(contact.id)
    end
    singular_success_model(200, Spree.t('live_stream.list_success'), contacts)
  end
  private
  def contact_params
    params.require(:contact).permit(:actor_id, :full_name, :email, :phone, :ip)
  end
  def contact_detail(id)
    contact = Contact.find(id)
    contact = {
      id: contact&.id || 0,
      actor_id: contact&.actor_id || 0,
      full_name: contact&.full_name || "",
      email: contact&.email&.split(",") || "",
      phone: contact&.phone&.split(",") || "",
      ip: contact&.ip || "",
      created_at: to_timestamp(contact&.created_at) || 0,
      updated_at: to_timestamp(contact&.updated_at) || 0
    }
    return contact
  end
end
