module Spree
  module Api
    module V1
      class UsersController < Spree::Api::BaseController
        include Swagger::Blocks
        include Response
        before_action :authenticate_user, :except => [:sign_up, :sign_in]

        swagger_path "/users/sign_up" do
          operation :post do
            key :summary, "SIGNUP"
            key :description, "Signing up with email and password"
            key :tags, [
              'Authentication'
            ]
            parameter do
              key :name, 'user[email]'
              key :in, :formData
              key :description, 'email'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password_confirmation]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, "Successfull"
              schema do
                key :'$ref', :user_response
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
        swagger_schema :user_response do
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
              key :'$ref', :user
            end
          end
        end
        swagger_schema :user do
          property :id do
            key :type, :integer
          end
          property :spree_api_key do
            key :type, :string
          end
          property :email do
            key :type, :string
          end
        end
        def sign_up
          @user = Spree::User.find_by_email(params[:user][:email])

          if @user.present?
            render "spree/api/users/user_exists", :status => 401 and return
          end

          @user = Spree::User.new(user_params)
          if !@user.save
            unauthorized
            return
          end
          @user.generate_spree_api_key!
          response_data = {
            id: @user.id || 0,
            spree_api_key: @user.spree_api_key || "",
            email: @user.email || ""
          }
          singular_success_model(200,  "User Created Successfully.", response_data)
        end

        swagger_path "/users/sign_in" do
          operation :post do
            key :summary, "Sign in"
            key :description, "Signing in with email and password"
            key :tags, [
              'Authentication'
            ]
            parameter do
              key :name, 'user[email]'
              key :in, :formData
              key :description, 'email'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, "Successfull"
              schema do
                key :'$ref', :user_response
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
        def sign_in
          @user = Spree::User.find_by_email(params[:user][:email])
          if !@user.present? || !@user.valid_password?(params[:user][:password])
            unauthorized
            return
          else
            @user.generate_spree_api_key! if @user.spree_api_key.blank?
            response_data = {
              id: @user.id || 0,
              spree_api_key: @user.spree_api_key || "",
              email: @user.email || ""
            }
            singular_success_model(200,  "User Sign in Successfully.", response_data)
          end
        end


        def user_params
          params.require(:user).permit(:email, :password, :password_confirmation)
        end

      end
    end
  end
end
