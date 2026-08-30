Rails.application.routes.draw do
  get "/.well-known/openid-configuration", to: "discovery#openid"
  get "/.well-known/oauth-authorization-server", to: "discovery#openid"
  get "/.well-known/jwks.json", to: "discovery#jwks"

  get "/authorize", to: "authorize#show", as: :authorize

  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  get "/login/otp", to: "sessions#second_factor", as: :second_factor
  post "/login/otp", to: "sessions#verify_second_factor"
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout

  get "/consent", to: "consents#show", as: :consent
  post "/consent", to: "consents#create"

  post "/token", to: "tokens#create"
  post "/revoke", to: "revocations#create"
  match "/userinfo", to: "userinfo#show", via: %i[get post]

  post "/register", to: "registrations#create"
  get "/register/:client_id", to: "registrations#show", as: :registration
  put "/register/:client_id", to: "registrations#update"
  delete "/register/:client_id", to: "registrations#destroy"

  get "up" => "rails/health#show", as: :rails_health_check

  root "account#index"
end
