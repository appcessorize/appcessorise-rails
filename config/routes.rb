Rails.application.routes.draw do
  get "documentation", to: "documentation#index"
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "pages#home"

  get "about", to: "pages#about"
  get "api-docs", to: "pages#api_docs"
  get "products", to: "products#index"
  get "products/:id", to: "products#show", as: :product
  get "dashboard", to: "dashboard#index"

  # Checkout routes
  resource :checkout, only: [ :new, :create ] do
    get :success, on: :collection
    get :failure, on: :collection
  end

  # Allow GET for payment confirmation (Stripe redirect)
  get "checkout", to: "checkouts#create"

  # Orders
  resources :orders, only: [ :index, :show ]

  # Contact form
  get "contact", to: "contacts#new"
  resources :contacts, only: [ :create, :index ]

  # Printful mockup checkout
  get "checkout/:mockup_id", to: "checkouts#mockup", as: :checkout_mockup

  # API routes
  namespace :api do
    namespace :v1 do
      resources :mockups, only: [ :create ]
      resources :orders, only: [ :create ]
    end
  end

  # Webhooks
  post "webhooks/printful", to: "webhooks#printful"
end
