Rails.application.routes.draw do
  # This line mounts Spree's routes at the root of your application.
  # This means, any requests to URLs such as /products, will go to
  # Spree::ProductsController.
  # If you would like to change where this engine is mounted, simply change the
  # :at option to something different.
  #
  # We ask that you don't use the :as option here, as Spree relies on it being
  # the default of "spree".

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
      resources :message_support, only: [:index]
    end

    get "/messages" => "messages#index"
    get "/messages/support" => "messages#message_support"
    get "pages/about_us" => "pages#about_us"

    resources :messages, only: [:index] do
      resources :message_support, only: [:index]
    end 

    get "/messages" => "messages#index"
    get "/messages/support" => "messages#message_support"

    # kludge
    get "/messages/one" => "messages#thread_list_one"
    get "/messages/two" => "messages#thread_list_two"

    resources :live_stream do
      collection do
        get :generate_playback
      end
    end
    resources :contacts
    
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
      resources :pages, only: [:index, :show], param: :slug
      resources :contacts
      resources :messages
    end
  end
  namespace :admin do
    resources :menu_items, except: :show do
      member do
        get :children
      end
    end
  end

    # This line mounts Spree's routes at the root of your application.
    # This means, any requests to URLs such as /products, will go to
    # Spree::ProductsController.
    # If you would like to change where this engine is mounted, simply change the
    # :at option to something different.
    #
    # We ask that you don't use the :as option here, as Spree relies on it being
    # the default of "spree".
    # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end