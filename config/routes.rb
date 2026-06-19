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
        post :bump_priority
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
        post  :cancel
        patch :prioritize
      end
      collection do
        patch :bulk_prioritize
      end
    end

    # Maintenance actions (queue cleanup, etc.).
    resource :housekeeping, only: :show, controller: :housekeeping do
      post :abort_pending_tasks
    end

    # Page-view analytics dashboard.
    resource :analytics, only: :show, controller: :analytics
  end

  # Worker-facing task queue API (bearer-token protected).
  namespace :api do
    get  "tasks/next",         to: "tasks#claim"
    post "tasks/:id/complete", to: "tasks#complete"
    post "tasks/:id/fail",     to: "tasks#mark_failed"
  end

  # Public-facing site (no auth): latest translated/refined news, magazine style.
  # The (:lang) optional segment makes `lang: "en"` a URL path prefix (/en/…)
  # rather than a query param, so default_url_options propagates it cleanly.
  scope "(:lang)", constraints: { lang: /en/ } do
    resources :news, only: %i[index show]
    get "search",             to: "news#search", as: :news_search
    get "category/:category", to: "news#index",  as: :category
  end
  get "/en", to: "news#index", defaults: { lang: "en" }, as: :en_root
  get "sitemap.xml", to: "news#sitemap", defaults: { format: "xml" },  as: :sitemap
  get "robots.txt",  to: "news#robots",  defaults: { format: "text" }, as: :robots
  get "llms.txt",    to: "news#llms",    defaults: { format: "text" }, as: :llms

  root to: "news#index"
end
