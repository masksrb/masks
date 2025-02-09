Rails.application.routes.draw do
  jobs_path = "/jobs"

  mask jobs_path, managers_only: true
  mount MissionControl::Jobs::Engine => jobs_path

  use_masks

  get "up" => "rails/health#show", :as => :rails_health_check

  Rails.application.routes.default_url_options = Masks.default_url_options
end
