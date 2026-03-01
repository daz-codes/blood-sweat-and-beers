Rails.application.routes.draw do
  delete "sign_out", to: "sessions#destroy", as: :sign_out
  get "sign_in", to: "sessions#new", as: :sign_in
  resource :registration, only: [:new, :create]
  resource :session, only: [:new, :create, :destroy]
  resources :passwords, param: :token, only: [:new, :create, :edit, :update]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :workouts, only: [ :new, :create, :show, :edit, :update, :destroy ] do
    member do
      get   :log
      patch :save_template
      post  :like, to: "workout_likes#toggle"
      post  :clone
      post  :remix
      post  :save
    end
  end
  get "library", to: "workouts#index", as: :library
  get "workout_log", to: "workout_logs#index", as: :workout_log_index

  resources :workout_logs, only: [ :create, :show ] do
    resources :comments, only: [ :index, :create, :destroy ]
  end

  get "feed", to: "feed#index", as: :feed
  resource :profile, only: [ :edit, :update ]

  resources :users, only: [ :index, :show ]
  resources :follows, only: [ :create, :destroy, :index ] do
    collection { get :pending_count }
  end
  resources :follows, only: [] do
    member { patch :accept }
  end

  # Defines the root path route ("/")
  root "feed#index"
end
