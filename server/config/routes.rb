Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  get "up" => "health#show", as: :health

  mount Masks::Server::Engine, at: "/"
end
