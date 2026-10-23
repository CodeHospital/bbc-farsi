Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Each section below only matches on its own host and in a process whose
  # APP_ROLE serves it (see AppHosts / AppRole). Without admin_base_url in
  # credentials there is no split: every section answers on any host and the
  # admin UI stays under /admin. With it set, the admin UI lives at the root of
  # the admin host — helper names (admin_articles_path, …) don't change.
  admin_path_prefix  = AppHosts.split? ? "/" : "admin"
  api_landing_path   = AppHosts.api_landing_at_root? ? "/" : "/api"
  worker_path_prefix = AppHosts.split? && AppHosts.worker_host.present? ? "/" : "worker"

  # ── Admin (admin.khabarestan.com) ───────────────────────────────────────────
  constraints(AppHosts.constraint_for(:admin)) do
    # Only admin pages subscribe to live updates.
    mount ActionCable.server => "/cable"

    namespace :admin, path: admin_path_prefix do
      root "dashboard#index"

      get  "login",  to: "sessions#new",     as: :login
      post "login",  to: "sessions#create"
      delete "logout", to: "sessions#destroy", as: :logout

      resources :password_resets, only: %i[new create edit update], param: :token

      resources :feeds, only: %i[index new create edit update destroy] do
        member     { patch :toggle; post :fetch; patch :schedule; patch :autopost_channel }
        collection { post :seed }
      end

      resources :edit_links, only: :destroy

      resources :articles, only: %i[index show] do
        resources :edit_links, only: :create
        member do
          post :rewrite
          post :multi_rewrite
          post :translate
          post :translate_original
          post :multi_translate
          post :archive
          post :unarchive
          post :bump_priority
          post :analyze
          patch :update_analysis
        end
        collection do
          post :bulk_rewrite
          post :bulk_translate
          post :bulk_analyze
          post :analyze_missing
        end
      end

      resources :rewrites, only: %i[index show edit update] do
        member do
          post :rerun
          post :activate
          post :archive
        end
        collection do
          post :bulk_rerun
        end
      end

      resources :prompts, only: %i[index show edit update] do
        member { post :revert }
      end

      resources :translations, only: %i[index show edit update] do
        member do
          post :rerun
          post :activate
          post :refine
          post :post_to_channel
          post :archive
          post :unarchive
          post :toggle_manual_edit
        end
        collection do
          post :bulk_rerun
          post :bulk_refine
        end
      end

      # Edits by editors flagged `requires_edit_approval`, awaiting review.
      resources :pending_edits, only: %i[index show destroy] do
        member do
          post :approve
          post :reject
        end
      end

      # Phrases that make feed ingestion skip an entry (admin-only).
      resources :skip_phrases, only: %i[index create update destroy] do
        member { patch :toggle }
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

      # Cached IP → country geolocation lookups.
      resources :ip_geolocations, only: %i[index destroy]

      # Admin/editor accounts (admin-only).
      resources :users, only: %i[index new create edit update] do
        member { patch :toggle }
      end

      # System-wide "who did what" audit log (admin-only).
      resources :activity_logs, only: :index
    end
  end

  # ── API (api.khabarestan.com) ───────────────────────────────────────────────
  constraints(AppHosts.constraint_for(:api)) do
    # Public landing page with stats on the tasks processed through the API
    # (ApiLandingController). "/" on the API host, /api otherwise.
    constraints(AppHosts.api_landing_constraint) do
      get api_landing_path, to: "api_landing#show", as: :api_landing
    end

    # Worker-facing task queue API (bearer-token protected).
    namespace :api do
      get  "tasks/next",         to: "tasks#claim"
      post "tasks/:id/complete", to: "tasks#complete"
      post "tasks/:id/fail",     to: "tasks#mark_failed"

      # Public webhook llmarkt (vibeearning) POSTs job results to. Auth is the
      # signed token in the query string, not the worker bearer token.
      post "llm_callbacks",      to: "llm_callbacks#create"

      # Public webhook Telegram POSTs admin-bot button taps to. Auth is the
      # X-Telegram-Bot-Api-Secret-Token header, not the worker bearer token.
      post "telegram_admin/webhook", to: "telegram_admin#webhook"
    end
  end

  # ── Worker status (worker.khabarestan.com) ──────────────────────────────────
  # Poller + task-queue health; anyone sees the summary, signed-in users the
  # details (WorkerStatusController). /worker on the public host when there is
  # no worker_base_url.
  constraints(AppHosts.constraint_for(:worker)) do
    scope worker_path_prefix, as: :worker do
      root to: "worker_status#show"
      get "status", to: "worker_status#show", as: :status

      get    "login",  to: "worker_sessions#new",     as: :login
      post   "login",  to: "worker_sessions#create"
      delete "logout", to: "worker_sessions#destroy", as: :logout
    end
  end

  # ── Public portal (www.khabarestan.com) ─────────────────────────────────────
  constraints(AppHosts.constraint_for(:public)) do
    # khabarestan.com ↔ www.khabarestan.com: the twin of app_base_url's host
    # 301-redirects to the canonical public URL, keeping the path and query.
    if AppHosts.split?
      constraints(->(request) { AppHosts.public_host_alias_request?(request) }) do
        match "(*any_path)", via: %i[get head], format: false,
              to: redirect(status: 301) { |_path_params, request| AppHosts.canonical_public_url(request) }
      end
    end

    # Old /admin bookmarks and links keep working after the split.
    if AppHosts.split?
      get "admin(/*admin_path)", format: false,
          to: redirect(status: 301) { |path_params, request| AppHosts.admin_redirect_url(path_params[:admin_path], request.query_string) }
    end

    # Public "magic link" for proposing an edit to one article without an
    # account (see EditLink / GuestEditsController).
    get  "edit/:token",        to: "guest_edits#show",   as: :guest_edit
    post "edit/:token",        to: "guest_edits#create"
    get  "edit/:token/thanks", to: "guest_edits#thanks", as: :guest_edit_thanks

    # Public-facing site (no auth): latest translated/refined news, magazine style.
    # The (:lang) optional segment makes `lang: "en"` a URL path prefix (/en/…)
    # rather than a query param, so default_url_options propagates it cleanly.
    scope "(:lang)", constraints: { lang: /en/ } do
      resources :news, only: %i[index show]
      get "search",             to: "news#search", as: :news_search
      get "feed",               to: "news#feed",   as: :news_feed, defaults: { format: "xml" }
      get "category/:category", to: "news#index",  as: :category
    end
    get "/en", to: "news#index", defaults: { lang: "en" }, as: :en_root
    get "sitemap.xml", to: "news#sitemap", defaults: { format: "xml" },  as: :sitemap
    get "robots.txt",  to: "news#robots",  defaults: { format: "text" }, as: :robots
    get "llms.txt",    to: "news#llms",    defaults: { format: "text" }, as: :llms

    root to: "news#index"
  end
end
