Rails.application.routes.draw do
  jobs_path = "/masks/jobs"

  mask jobs_path
  mount MissionControl::Jobs::Engine => jobs_path

  use_masks(oidc: true)

  get "up" => "rails/health#show", :as => :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", :as => :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", :as => :pwa_manifest
end

Rails.application.routes.default_url_options = Masks.default_url_options
