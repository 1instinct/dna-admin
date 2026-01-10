module Spree
  module Api
    module V1
      class UsersController < Spree::Api::BaseController
        include Swagger::Blocks
        include Response
        include Spree::Api::V1::GlobalHelper
        before_action :authenticate_user, :except => [:sign_up, :sign_in, :profile]

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
            error_model(401, Spree.t('user.error.user_exists'))
            return
          end

          @user = Spree::User.new(user_params)
          if !@user.save
            error_model(400, @user.errors.full_messages.join(','))
            return
          end
          @user.generate_spree_api_key!
          response_data = {
            id: @user.id || 0,
            spree_api_key: @user.spree_api_key || "",
            email: @user.email || ""
          }
          singular_success_model(200,  Spree.t('user.success.sign_up'), response_data)
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
            error_model(401, Spree.t('user.error.email_password_unmatch'))
            return
          else
            @user.generate_spree_api_key! if @user.spree_api_key.blank?
            response_data = {
              id: @user.id || 0,
              spree_api_key: @user.spree_api_key || "",
              email: @user.email || ""
            }            
            singular_success_model(200,  Spree.t('user.success.sign_in'), response_data)
          end
        end


        swagger_path "/users/{id}/profile" do
          operation :get do
            key :summary, "GET USER PROFILE"
            key :description, "Get public user profile with optional authentication for extended info"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (optional - provides extended info if viewing own profile)'
              key :required, false
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successful'
              schema do
                key :'$ref', :user_profile_response
              end
            end
            
            response 404 do
              key :description, 'User not found'
            end
          end
        end
        
        swagger_schema :user_profile_response do
          key :required, [:response_code, :response_message]
          property :response_code do
            key :type, :integer
          end
          property :response_message do
            key :type, :string
          end
          property :response_data do
            key :'$ref', :user_profile
          end
        end
        
        swagger_schema :user_profile do
          property :id do
            key :type, :integer
          end
          property :email do
            key :type, :string
          end
          property :first_name do
            key :type, :string
          end
          property :last_name do
            key :type, :string
          end
          property :followers_count do
            key :type, :integer
          end
          property :following_count do
            key :type, :integer
          end
          property :is_following do
            key :type, :boolean
            key :description, 'True if current user is following this profile (requires authentication)'
          end
          property :public_favorites do
            key :type, :array
            items do
              key :'$ref', :favorite_product
            end
          end
        end
        
        swagger_schema :favorite_product do
          property :id do
            key :type, :integer
          end
          property :variant_id do
            key :type, :integer
          end
          property :product_id do
            key :type, :integer
          end
          property :name do
            key :type, :string
          end
          property :slug do
            key :type, :string
          end
          property :price do
            key :type, :string
          end
        end
        
        def profile
          user = Spree::User.find_by_id(params[:id])
          unless user
            return error_model(404, "User not found")
          end
          
          # Get public favorites with product details
          public_favorites = user.favorites.public_favorites.includes(variant: :product).recent.map do |fav|
            {
              id: fav.id,
              variant_id: fav.variant_id,
              product_id: fav.product&.id,
              name: fav.product&.name,
              slug: fav.product&.slug,
              price: fav.variant&.price&.to_s
            }
          end
          
          # Check if current user is following this profile
          is_following = @current_api_user.present? ? UserFollow.following?(@current_api_user, user) : false
          
          profile_data = {
            id: user.id,
            email: user.email,
            first_name: user.bill_address&.firstname || "",
            last_name: user.bill_address&.lastname || "",
            followers_count: user.followers.count,
            following_count: user.followings.count,
            is_following: is_following,
            public_favorites: public_favorites
          }
          
          singular_success_model(200, "User profile retrieved successfully", profile_data)
        end
        
        swagger_path "/users/{id}/follow" do
          operation :post do
            key :summary, "FOLLOW USER"
            key :description, "Follow a user"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID to follow'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token'
              key :required, true
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successfully followed user'
              schema do
                key :'$ref', :follow_response
              end
            end
            
            response 400 do
              key :description, 'Error'
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
          end
        end
        
        swagger_path "/users/{id}/unfollow" do
          operation :post do
            key :summary, "UNFOLLOW USER"
            key :description, "Unfollow a user"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID to unfollow'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token'
              key :required, true
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successfully unfollowed user'
              schema do
                key :'$ref', :follow_response
              end
            end
            
            response 400 do
              key :description, 'Error'
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
          end
        end
        
        swagger_schema :follow_response do
          key :required, [:response_code, :response_message]
          property :response_code do
            key :type, :integer
          end
          property :response_message do
            key :type, :string
          end
          property :response_data do
            property :is_following do
              key :type, :boolean
            end
            property :followers_count do
              key :type, :integer
            end
          end
        end
        
        def follow
          user_to_follow = Spree::User.find_by_id(params[:id])
          unless user_to_follow
            return error_model(404, "User not found")
          end
          
          if @current_api_user.id == user_to_follow.id
            return error_model(400, "Cannot follow yourself")
          end
          
          # Check if already following
          if UserFollow.following?(@current_api_user, user_to_follow)
            return singular_success_model(200, "Already following this user", {
              is_following: true,
              followers_count: user_to_follow.followers.count
            })
          end
          
          # Create follow
          UserFollow.create(follower: @current_api_user, following: user_to_follow)
          
          singular_success_model(200, "Successfully followed user", {
            is_following: true,
            followers_count: user_to_follow.followers.count
          })
        end
        
        def unfollow
          user_to_unfollow = Spree::User.find_by_id(params[:id])
          unless user_to_unfollow
            return error_model(404, "User not found")
          end
          
          # Find and destroy follow relationship
          follow = UserFollow.find_by(follower: @current_api_user, following: user_to_unfollow)
          if follow
            follow.destroy
            singular_success_model(200, "Successfully unfollowed user", {
              is_following: false,
              followers_count: user_to_unfollow.followers.count
            })
          else
            error_model(400, "Not following this user")
          end
        end

        def user_params
          params.require(:user).permit(:email, :password, :password_confirmation)
        end

      end
    end
  end
end
