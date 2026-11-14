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
  # In-app purchases (App Store / Google Play): app API, store notifications, admin.
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      namespace :iap do
        resources :transactions, only: %i[index show create]
        resources :entitlements, only: :index
        resources :products, only: :index
        post :restore, to: 'restores#create'
        get :account_token, to: 'account_tokens#show'
        post 'apple/notifications', to: 'apple_notifications#create', as: :apple_notifications
        post 'google/notifications', to: 'google_notifications#create', as: :google_notifications
      end
    end
  end

  namespace :admin, path: Spree.admin_path do
    resources :iap_transactions, only: %i[index show] do
      member { post :revoke }
    end
    resources :iap_products, except: :show
    resources :entitlements, only: [] do
      member { post :revoke }
    end
  end

  namespace :admin, path: Spree.admin_path do
    resource :theme, only: [:show, :update], controller: 'theme'

    resources :messages do
      collection do
        get :conversation
        get :conversations
      end
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
    
    resources :homepage_sections do
      member do
        post :move_up
        post :move_down
        patch :toggle_visibility
      end
    end

    resources :content_assets, except: [:show]

    resources :contacts

    resources :products, only: [] do
      resources :product_videos, except: :show do
        collection do
          post :update_positions
        end
      end
    end

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

    # Profile moderation.
    resources :content_reports, only: [:index, :show] do
      member do
        post :dismiss
        post :hide_profile
        post :remove_photo
        post :clear_bio
        post :lock_account
      end
    end
    resources :user_profiles, only: [] do
      member do
        post :hide
        post :unhide
      end
    end
    resources :users, only: [] do
      resource :account_lock, only: [:create, :destroy]
    end
  end
  namespace :admin do
    resources :menu_items, except: :show do
      member do
        get :children
      end
    end
  end

  namespace :api, constraints: { format: 'json' } do
    namespace :v1 do
      resources :live_stream do
        member do
          post :add_watcher
          post :remove_watcher
        end
      end
      resources :homepage_sections
      resources :content_assets, only: [:index, :show, :create, :update, :destroy]
      resources :favorites, only: [:index, :destroy] do
        collection do
          post :toggle
          get :check
        end
        member do
          post :toggle_public
        end
      end
      resources :users do
        collection do
          post :sign_up
          post :sign_in
        end
        member do
          get :profile
          post :follow
          post :unfollow
        end
      end
      resources :pages, only: [:index, :show], controller: 'pages', param: :slug
      # The signed-in user deletes their own account (OAuth bearer required).
      resource :account, only: [:destroy], controller: 'account', defaults: { format: 'json' }
      # Public profiles, follows, blocks and reports.
      defaults format: 'json' do
        resource :profile, only: [:show, :update], controller: 'profile' do
          put :avatar, action: :update_avatar
          delete :avatar, action: :destroy_avatar
        end
        resources :profiles, only: [:show], param: :handle do
          collection do
            get :handle_available
          end
          member do
            post :follow
            delete :follow, action: :unfollow
          end
        end
        resources :blocks, only: [:index, :create, :destroy], param: :handle
        resources :reports, only: [:create]
      end
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

    namespace :v2 do
      namespace :storefront do
        resource :store, only: [:show], path: 'default_store', as: :default_store, controller: 'store'
      end
    end
  end
end

# App feedback: the app's endpoint and the admin's Feedback tab.
Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      post :feedback, to: 'feedback#create', as: :feedback
    end
  end

  namespace :admin, path: Spree.admin_path do
    resources :app_feedbacks, path: 'feedback', only: %i[index show update] do
      collection { post :bulk_archive }
    end
  end
end

# Affiliate program: click tracking, order attribution, the affiliate's own API and the admin tab.
Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      post 'affiliate/clicks', to: 'affiliate_clicks#create', as: :affiliate_clicks
      patch 'orders/current/affiliate', to: 'order_affiliates#update', as: :current_order_affiliate
      resource :affiliate, only: %i[show create update], controller: 'affiliate' do
        get :stats
        get :commissions
        get :payouts
        get :code_available
      end
    end
  end

  # Not /admin/affiliates: the spree_reffiliate gem's admin pages live there, and its
  # admin_affiliate_commissions route name is taken too.
  namespace :admin, path: Spree.admin_path do
    resources :affiliate_accounts, only: %i[index show update] do
      member do
        post :approve
        post :reject
        post :suspend
        post :reinstate
      end
    end
    resources :affiliate_commissions, only: :index, as: :affiliate_account_commissions do
      member { post :void }
    end
    resources :affiliate_payouts, only: %i[index new create]
  end
end
