Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount RubyLLM::Monitoring::Engine, at: "/monitoring"
  mount Leva::Engine, at: "/leva"

  resources :chats, only: [ :index, :show, :destroy ] do
    collection do
      post :batch
    end
  end
  resources :application_mails do
    collection do
      post :batch
    end
  end
  resources :interviews do
    collection do
      post :batch
      post :export_gist
    end
  end

  namespace :evaluation do
    root to: "dashboard#show"
    resources :metrics, only: [ :index, :edit, :update, :create, :destroy ] do
      collection do
        post :generate
      end
    end
    get "prompts/:id/diff", to: "prompt_diffs#show", as: :prompt_diff
    resources :datasets, only: [] do
      collection do
        post :generate
      end
    end
    resources :experiments, only: [ :index, :show, :new, :create ] do
      member do
        post :improve
        post :activate
        get "compare/:candidate_id", action: :compare, as: :compare
        get :status_frame
        get "metrics/:metric_name", action: :metric_results, as: :metric_results
      end
      collection do
        post :wizard_step
        get :prompt_versions
      end
    end
  end

  namespace :orchestration do
    resources :agents do
      member do
        patch :toggle
      end
    end
    resources :actions
    resources :pipeline_runs, only: [ :index ], controller: "all_pipeline_runs"
    resources :pipelines do
      member do
        post :run
        patch :toggle
      end
      resources :pipeline_runs, only: [ :index, :show ]
      resources :steps, only: [ :create, :update, :destroy ] do
        member do
          patch :move_up
          patch :move_down
          patch :toggle
        end
        resources :step_actions, only: [ :create, :destroy ]
      end
    end
  end

  resources :models, only: [ :index ] do
    collection do
      post :sync
    end
  end

  namespace :settings do
    resources :email_connectors do
      member do
        post :test
        get :setup
      end
      collection do
        get :oauth_callback
      end
    end
  end

  get "home", to: "home#index"
  root to: "home#index"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
