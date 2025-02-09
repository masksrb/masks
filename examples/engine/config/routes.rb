Rails.application.routes.draw do
  use_masks # See https://masksrb.github.io/guides/rails for more information...

  mask "/demo"
  mask "/", optional: true

  # This route is masked above, so it is only accessible after login.
  get "demo", to: "demo#index"
  get "demo/:id", to: "demo#show"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "welcome#index"
end
