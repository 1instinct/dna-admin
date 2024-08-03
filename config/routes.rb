Rails.application.routes.draw do
  # This line mounts Spree's routes at the root of your application.
  mount Spree::Core::Engine, at: '/'

  resources :apidocs, only: [:index] do
    collection do
      get 'swagger_ui'
    end
  end
end

Spree::Core::Engine.add_routes do
  namespace :admin, path: Spree.admin_path do
    resources :messages do      
      collection do
        get :conversation
        get :conversations
      end
      resources :message_support, only: [:index]
    end 

    get "/messages/support" => "messages#message_support"
    get "/menu_items/show_menu_item" => "menu_items#show_menu_item"
    get "/menu_locations/show_menu_location" => "menu_locations#show_menu_location"

    resources :live_stream do
      collection do
        get :generate_playback
      end
    end
    resources :contacts
    resources :threads do
      member do
        get :conversation
      end
    end

    resources :menu_locations do
      resources :menu_items
    end
    resources :menu_items, except: :show do
      member do
        get :children
      end
    end
  end

  namespace :api, constraints: { format: 'json' } do
    namespace :v1 do
      resources :live_stream
      resources :users do
        collection do
          post :sign_up
          post :sign_in
        end
      end
      resources :pages, only: [:index, :show], controller: 'pages', param: :slug
      resources :contacts
      resources :messages
      resources :threads
      resources :menu_items, only: [:index, :show] do
        member do
          get :children
        end
      end
      resources :menu_locations, only: [:index, :show] do
        member do
          get :menu_items
        end
      end
    end
  end
end
