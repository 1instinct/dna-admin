Rails.application.routes.draw do

  mount Spree::Core::Engine, at: '/'
  
end

Spree::Core::Engine.add_routes do
  namespace :admin, path: Spree.admin_path do
    resources :messages, only: [:index] do
      resources :message_support, only: [:index]
    end 

    get "/messages" => "messages#index"
    get "/messages/support" => "messages#message_support"
    
  end
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :messages, only: [:index]
    end
  end
end