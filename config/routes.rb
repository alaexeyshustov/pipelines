Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :chats, only: [ :index, :show, :destroy ]
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

  namespace :orchestration do
    resources :actions
    resources :pipelines do
      member do
        post :run
      end
      resources :pipeline_runs, only: [ :index, :show ]
      resources :steps, only: [ :create, :update, :destroy ] do
        member do
          patch :move_up
          patch :move_down
        end
        resources :step_actions, only: [ :create, :destroy ]
      end
    end
  end

  root to: "chats#index"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
