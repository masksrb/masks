Rails.application.routes.draw do
  get '/protected', to: 'protected#show'
end
