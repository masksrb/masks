require "action_controller/railtie"
require "action_view/railtie"
require "masks/rails"

module Dummy
  class Application < ::Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = "masks-engine-test-secret-key-base-which-is-long-enough"
    config.logger = Logger.new(IO::NULL)
    config.active_support.deprecation = :silence
    config.hosts.clear
    config.session_store :cookie_store, key: "_masks_rails_test"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
    config.middleware.use ActionDispatch::Flash
  end
end

class CredentialStore
  def initialize
    @held = {}
  end

  def [](host)
    @held[host]
  end

  def connect!(host, client_id: "test-client", client_secret: "test-secret")
    @held[host] = { client_id: client_id, client_secret: client_secret }
  end

  def write(host, registration)
    @held[host] = {
      client_id: registration.client_id,
      client_secret: registration.client_secret,
      registration_access_token: registration.access_token,
      registration_client_uri: registration.uri
    }
  end

  def forget!(host)
    @held.delete(host)
  end

  def clear!
    @held = {}
  end
end

CREDENTIALS = CredentialStore.new

class PagesController < ActionController::Base
  include Masks::Rails::Authentication

  before_action :authenticate_masks!, only: :dashboard

  def home
    render plain: "home"
  end

  def dashboard
    render plain: "dashboard for #{masks_identity&.fetch('sub', nil)}"
  end
end

class CatalogController < ActionController::Base
  include Masks::Rails::Authentication
  include Masks::Rails::ProtectedResource

  masks_protect! scope: "catalog:read"

  def show
    render json: { "subject" => masks_claims.subject, "scopes" => masks_claims.scopes }
  end
end

class ApiController < ActionController::Base
  include Masks::Rails::ProtectedResource

  masks_protect! scope: "catalog:read"

  def show
    render json: { "subject" => masks_claims.subject }
  end
end

class BareController < ActionController::Base
  def show
    render json: {
      "authentication" => respond_to?(:masks_signed_in?, true),
      "config" => respond_to?(:masks_config, true)
    }
  end
end

class AskedController < ActionController::Base
  include Masks::Rails::Authentication

  def show
    render json: {
      "authentication" => respond_to?(:masks_signed_in?, true),
      "config" => respond_to?(:masks_config, true)
    }
  end
end

Dummy::Application.initialize!

Rails.application.routes.draw do
  mount Masks::Rails::Engine, at: "/auth", as: :masks

  get "/catalog", to: "catalog#show"
  get "/api", to: "api#show"
  get "/bare", to: "bare#show"
  get "/asked", to: "asked#show"
  get "/dashboard", to: "pages#dashboard"
  root to: "pages#home"
end
