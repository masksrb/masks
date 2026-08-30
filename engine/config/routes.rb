Masks::Rails::Engine.routes.draw do
  get "/", to: "sessions#start", as: :start
  get "/callback", to: "sessions#callback", as: :callback
  match "/logout", to: "sessions#destroy", via: %i[get post delete], as: :logout
end
