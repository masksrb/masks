Rails.application.routes.draw do
  get "/.well-known/openid-configuration", to: "discovery#openid"
  get "/.well-known/oauth-authorization-server", to: "discovery#openid"
  get "/.well-known/jwks.json", to: "discovery#jwks"

  match "/authorize", to: "authorize#show", via: %i[get post], as: :authorize

  get "/login", to: "logins#show", as: :login
  post "/login", to: "logins#update"
  delete "/login", to: "logins#destroy"
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout

  get "/handshake", to: "handshakes#show", as: :handshake
  post "/handshake", to: "handshakes#create"

  get "/consent", to: "consents#show", as: :consent
  post "/consent", to: "consents#create"

  post "/token", to: "tokens#create"
  post "/revoke", to: "revocations#create"
  post "/introspect", to: "introspections#create"
  match "/userinfo", to: "userinfo#show", via: %i[get post]

  post "/register", to: "registrations#create"
  get "/register/:client_id", to: "registrations#show", as: :registration
  put "/register/:client_id", to: "registrations#update"
  delete "/register/:client_id", to: "registrations#destroy"

  get "up" => "rails/health#show", as: :rails_health_check

  root "account#index"
end
