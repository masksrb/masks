Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  get "up" => "health#show", as: :health
  get "up/jobs" => "health#jobs", as: :health_jobs

  mount Masks::Server::Engine, at: "/"
end
