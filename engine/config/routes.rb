Masks::Server::Engine.routes.draw do
  get "/.well-known/openid-configuration", to: "discovery#openid"
  get "/.well-known/oauth-authorization-server", to: "discovery#openid"
  get "/.well-known/jwks.json", to: "discovery#jwks"
  get "/.well-known/oauth-protected-resource(/*resource)", to: "discovery#resource"

  match "/authorize", to: "authorize#show", via: %i[get post], as: :authorize
  post "/par", to: "pushed_authorizations#create", as: :pushed_authorization
  post "/device_authorization", to: "device_authorizations#create", as: :device_authorization

  get "/device", to: "device_verifications#show", as: :device_verification
  post "/device", to: "device_verifications#create", as: :device_code

  get "/themes/:digest.css", to: "themes#show", as: :theme, format: false,
                             constraints: { digest: /[0-9a-f]{32}/ }

  get "/login", to: "logins#show", as: :login
  post "/login", to: "logins#update"
  delete "/login", to: "logins#destroy"
  get "/login/provider/:key/callback", to: "logins#provider", as: :login_provider_callback
  post "/login/provider/:key/callback", to: "logins#posted_provider"
  get "/login/provider/:key/metadata", to: "provider_metadata#show", as: :login_provider_metadata
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout

  get "/invite/:token", to: "links#invitation", as: :invitation
  get "/reset/:token", to: "links#reset", as: :password_reset
  get "/verify/:token", to: "links#verify", as: :email_verification

  patch "/account/notifications", to: "notifications#update", as: :account_notifications
  patch "/account/password", to: "passwords#update", as: :account_password
  post "/account/verify", to: "verifications#create", as: :account_verification

  post "/account/passkeys/challenge", to: "passkeys#challenge", as: :passkey_challenge
  post "/account/passkeys", to: "passkeys#create", as: :passkeys
  delete "/account/passkeys/:id", to: "passkeys#destroy", as: :passkey

  patch "/account/devices/:id", to: "devices#update", as: :device
  delete "/account/devices/:id", to: "devices#destroy"

  post "/account/avatar", to: "avatars#create", as: :account_avatar
  delete "/account/avatar", to: "avatars#destroy"

  delete "/account/apps/:client_id", to: "apps#destroy", as: :account_app
  post "/account/connections", to: "connections#create", as: :account_connections
  delete "/account/connections/:id", to: "connections#detach", as: :account_connection
  delete "/account/delegations/:id", to: "delegations#destroy", as: :account_delegation

  scope constraints: { style: Regexp.union(Masks::Server::Avatars::STYLES), digest: /[0-9a-f]{16}/ } do
    get "/avatars/:uuid", to: "avatars#show", as: :avatar
    get "/avatars/:uuid/:style", to: "avatars#show", as: :styled_avatar
    get "/avatars/:uuid/:style/:digest", to: "avatars#show", as: :stamped_avatar
  end

  get "/clients/:client_id/logo", to: "client_logos#show", as: :client_logo, constraints: { client_id: %r{[^/]+} }

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

  get "/saml/metadata", to: "saml#metadata", as: :saml_metadata
  match "/saml/sso", to: "saml#sso", via: %i[get post], as: :saml_sso
  get "/saml/resume", to: "saml#resume", as: :saml_resume
  get "/saml/refused", to: "saml#refused", as: :saml_refused
  get "/saml/initiate/:client_id", to: "saml#initiate", as: :saml_initiate

  scope "/scim/v2", module: :scim, defaults: { format: :json } do
    get "ServiceProviderConfig", to: "metadata#service_provider_config"
    get "ResourceTypes", to: "metadata#resource_types"
    get "ResourceTypes/:id", to: "metadata#resource_type"
    get "Schemas", to: "metadata#schemas"
    get "Schemas/:id", to: "metadata#schema", constraints: { id: /[^\/]+/ }

    get "Users", to: "users#index"
    post "Users", to: "users#create"
    get "Users/:id", to: "users#show"
    put "Users/:id", to: "users#replace"
    patch "Users/:id", to: "users#update"
    delete "Users/:id", to: "users#destroy"
  end

  post "/manage/graphql", to: "manage/graphql#execute", as: :manage_graphql
  get "/manage(/*path)", to: "manage#index", as: :manage

  root "account#index"
end
