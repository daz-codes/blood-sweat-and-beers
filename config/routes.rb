Rails.application.routes.draw do
  delete "sign_out", to: "sessions#destroy", as: :sign_out
  get "sign_in", to: "sessions#new", as: :sign_in
  resource :registration, only: [ :new, :create ]
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]

  # OAuth callbacks
  get  "auth/:provider/callback", to: "omniauth_callbacks#create"
  post "auth/:provider/callback", to: "omniauth_callbacks#create"
  get  "auth/failure",            to: "omniauth_callbacks#failure"
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
      get   :export_pdf
      patch :save_template
      post  :like, to: "workout_likes#toggle"
      post  :clone
      post  :remix
      post  :save
      post  :regenerate
      post  :swap_exercise
    end
  end
  resources :programs, only: [ :new, :create, :show, :destroy ]
  get "library", to: "workouts#index", as: :library
  get "workout_log", to: "workout_logs#index", as: :workout_log_index
  get "calendar",     to: "workout_logs#calendar",     as: :calendar
  get "calendar/day", to: "workout_logs#calendar_day", as: :calendar_day

  resources :workout_logs, only: [ :create, :show ] do
    resources :comments, only: [ :index, :create, :destroy ]
  end

  get "feed", to: "feed#index", as: :feed
  resources :notifications, only: [ :index ]
  resources :challenge_entries, only: [ :create ]
  resource :profile, only: [ :show, :edit, :update ]
  resource :subscription, only: [] do
    patch :upgrade
    patch :downgrade
  end
  get  "progress",                    to: "progress#index",        as: :progress
  get  "progress/:test_key",          to: "progress#show",          as: :progress_test
  post "progress/:test_key/entries",  to: "progress#create_entry",  as: :progress_test_entries

  resources :users, only: [ :index, :show ] do
    collection { post :contacts_search }
  end
  resources :follows, only: [ :create, :destroy, :index ] do
    collection { get :pending_count }
  end
  resources :follows, only: [] do
    member { patch :accept }
  end

  # Defines the root path route ("/")
  root "feed#index"
end
