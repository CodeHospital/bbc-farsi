Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :admin do
    root "dashboard#index"

    get  "login",  to: "sessions#new",     as: :login
    post "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    resources :feeds, only: %i[index new create edit update destroy] do
      member     { patch :toggle }
      collection { post :seed }
    end

    resources :articles, only: %i[index show] do
      member do
        post :rewrite
        post :multi_rewrite
        post :translate
        post :multi_translate
        post :archive
        post :unarchive
      end
    end

    resources :rewrites, only: %i[index show edit update] do
      member do
        post :rerun
        post :activate
        post :archive
      end
    end

    resources :translations, only: %i[index show edit update] do
      member do
        post :rerun
        post :activate
        post :refine
        post :post_to_channel
        post :archive
      end
    end

    resources :telegram_channels, only: %i[index new create edit update destroy] do
      member { patch :toggle }
    end

    resources :telegram_posts, only: %i[index show]

    resources :ollama_servers, only: %i[index new create edit update destroy] do
      member { patch :toggle }
    end
  end

  root to: redirect("/admin")
end
