Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount ActionCable.server => "/cable"

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
        post :translate_original
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

    resources :tasks, only: %i[index show] do
      member do
        post  :retry
        patch :prioritize
      end
      collection do
        patch :bulk_prioritize
      end
    end
  end

  # Worker-facing task queue API (bearer-token protected).
  namespace :api do
    get  "tasks/next",         to: "tasks#claim"
    post "tasks/:id/complete", to: "tasks#complete"
    post "tasks/:id/fail",     to: "tasks#mark_failed"
  end

  root to: redirect("/admin")
end
