class Spree::Api::V1::ContactsController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  include Spree::Api::V1::GlobalHelper
  before_action :authenticate_user, :except => [:create]
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
      key :type, :array
      items do
        key :'$ref', :contact
      end
    end
  end
  def create
    contact = Contact.new(user_params)
    if contact.save
      response_data = {
        id: contact&.id,
        actor_id: contact&.actor_id,
        full_name: contact&.full_name,
        email: contact&.email,
        phone: contact&.phone,
        ip: contact&.ip,
        created_at: contact&.created_at,
        updated_at: contact&.updated_at
      }
      singular_success_model(200, Spree.t('contact.success.create'), response_data)
    else
      error_model(400, contact.errors.full_messages.join(','))
      return
    end
  end
  private
  def user_params
    params.require(:contact).permit(:actor_id, :full_name, :email, :phone, :ip)
  end
end
