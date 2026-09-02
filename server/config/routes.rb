Rails.application.routes.draw do
  get "/.well-known/openid-configuration", to: "discovery#openid"
  get "/.well-known/oauth-authorization-server", to: "discovery#openid"
  get "/.well-known/jwks.json", to: "discovery#jwks"
  get "/.well-known/oauth-protected-resource(/*resource)", to: "discovery#resource"

  match "/authorize", to: "authorize#show", via: %i[get post], as: :authorize

  get "/login", to: "logins#show", as: :login
  post "/login", to: "logins#update"
  delete "/login", to: "logins#destroy"
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout

  get "/invite/:token", to: "links#invitation", as: :invitation
  get "/reset/:token", to: "links#reset", as: :password_reset

  patch "/account/password", to: "passwords#update", as: :account_password

  get "/handshake", to: "handshakes#show", as: :handshake
  post "/handshake", to: "handshakes#create"

  post "/token", to: "tokens#create"
  post "/revoke", to: "revocations#create"
  post "/introspect", to: "introspections#create"
  match "/userinfo", to: "userinfo#show", via: %i[get post]

  post "/register", to: "registrations#create"
  get "/register/:client_id", to: "registrations#show", as: :registration
  put "/register/:client_id", to: "registrations#update"
  delete "/register/:client_id", to: "registrations#destroy"

  get "/connections", to: "connections#index", as: :connections
  post "/connections/token", to: "connections/tokens#create", as: :connection_token
  match "/connections/:provider/start", to: "connections#create", via: %i[get post], as: :connect
  get "/connections/:provider/callback", to: "connections#callback", as: :connection_callback
  delete "/connections/:id", to: "connections#destroy", as: :connection

  post "/manage/graphql", to: "manage/graphql#execute", as: :manage_graphql
  get "/manage(/*path)", to: "manage#index", as: :manage

  get "up" => "rails/health#show", as: :rails_health_check

  root "account#index"
end
