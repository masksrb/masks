require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "masks/server"

module Host
  class Application < ::Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.1
    config.eager_load = false
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :none
    config.action_controller.allow_forgery_protection = false
    config.secret_key_base = "a-host-app-secret-key-base-that-masks-must-never-sign-with"
    config.logger = Logger.new(IO::NULL)
    config.active_support.deprecation = :silence
    config.hosts.clear
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_method = :test
    config.active_record.maintain_test_schema = false
    config.session_store :cookie_store, key: "_host_session"

    config.masks.mode = :engine
    config.masks.database = :masks
    config.masks.tenant = "app"
  end
end

Host::Application.initialize!

class DashboardController < ActionController::Base
  include Masks::Server::Host

  before_action :require_masks_actor!, only: :show

  def show
    session[:host_seen] = true
    render plain: masks_actor.nickname
  end

  def note
    session[:host_note] = params[:note]
    head :ok
  end

  def read_note
    render plain: session[:host_note].to_s
  end
end

class HostJob < ActiveJob::Base
  def perform
  end
end

Rails.application.routes.draw do
  constraints(host: "auth.app.test") do
    mount Masks::Server::Engine, at: "/", as: :masks_server_on_subdomain
  end

  mount Masks::Server::Engine, at: "/auth"

  get "/dashboard", to: "dashboard#show"
  post "/note", to: "dashboard#note"
  get "/note", to: "dashboard#read_note"
end
