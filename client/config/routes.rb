Masks::Rails::Engine.routes.draw do
  get "/", to: "sessions#start", as: :start
  get "/session", to: "sessions#show", as: :session
  get "/avatar", to: "avatars#show", as: :avatar
  get "/callback", to: "sessions#callback", as: :callback
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout
  post "/logout/backchannel", to: "logouts#create", as: :backchannel_logout

  get "/handshake", to: "handshakes#show", as: :handshake
  post "/handshake", to: "handshakes#create"
  get "/handshake/callback", to: "handshakes#callback", as: :handshake_callback
  delete "/handshake", to: "handshakes#destroy"
end
