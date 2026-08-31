$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV["RAILS_ENV"] = "test"

require "minitest/autorun"
require_relative "support/issuer"
require_relative "support/dummy"
require "rails/dom/testing"

class EngineTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::Assertions

  SUBDOMAIN = "jons".freeze
  HOST = "jons.app.test".freeze

  setup do
    Masks::Client.registry.clear!
    CREDENTIALS.clear!
    configure!
  end

  def issuer
    TestIssuer.current
  end

  def configure!(**overrides)
    Masks::Rails.configure do |config|
      config.name = overrides.fetch(:name, "Catalog")
      config.issuer = overrides.fetch(:issuer, ->(request) { TestIssuer.current.url_for(request.host.split(".").first) })
      config.resource = overrides.fetch(:resource, ->(request) { "#{request.base_url}/mcp" })
      config.redirect_uri = overrides[:redirect_uri]
      config.credentials = overrides.fetch(:credentials, ->(request) { CREDENTIALS[request.host] })
      config.store = overrides.fetch(:store, ->(request, registration) { CREDENTIALS.write(request.host, registration) })
      config.resource_scopes = overrides.fetch(:resource_scopes, %w[catalog:read])
      config.scope = overrides.fetch(:scope, %w[openid profile email offline_access catalog:read])
      config.after_sign_in = overrides.fetch(:after_sign_in, "/")
      config.after_sign_out = overrides.fetch(:after_sign_out, "/")
      config.session_key = "masks"
    end
  end

  def connect!(host: HOST)
    CREDENTIALS.connect!(host)
  end
end

class EngineIntegrationTest < ActionDispatch::IntegrationTest
  SUBDOMAIN = EngineTest::SUBDOMAIN
  HOST = EngineTest::HOST

  setup do
    Masks::Client.registry.clear!
    CREDENTIALS.clear!
    configure!
  end

  def app
    Rails.application
  end

  def issuer
    TestIssuer.current
  end

  def host
    { "HTTP_HOST" => HOST }
  end

  def json
    JSON.parse(response.body)
  end

  def origin
    "http://#{HOST}"
  end

  def configure!(**overrides)
    Masks::Rails.configure do |config|
      config.name = overrides.fetch(:name, "Catalog")
      config.issuer = overrides.fetch(:issuer, ->(request) { TestIssuer.current.url_for(request.host.split(".").first) })
      config.resource = overrides.fetch(:resource, ->(request) { "#{request.base_url}/mcp" })
      config.redirect_uri = overrides[:redirect_uri]
      config.credentials = overrides.fetch(:credentials, ->(request) { CREDENTIALS[request.host] })
      config.store = overrides.fetch(:store, ->(request, registration) { CREDENTIALS.write(request.host, registration) })
      config.resource_scopes = overrides.fetch(:resource_scopes, %w[catalog:read])
      config.scope = overrides.fetch(:scope, %w[openid profile email offline_access catalog:read])
      config.after_sign_in = overrides.fetch(:after_sign_in, "/")
      config.after_sign_out = overrides.fetch(:after_sign_out, "/")
      config.session_key = "masks"
    end
  end

  def connect!
    CREDENTIALS.connect!(HOST)
  end

  def sign_in!
    connect!

    get "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host
  end

  def shake_hands!
    get "/auth/handshake", headers: host
    post "/auth/handshake", headers: host

    started = URI.decode_www_form(URI.parse(response.location).query).to_h
    token = issuer.approve!(SUBDOMAIN)

    get "/auth/handshake/callback?initial_access_token=#{token}&state=#{started['state']}" \
        "&iss=#{CGI.escape(issuer.url_for(SUBDOMAIN))}", headers: host

    started
  end
end
