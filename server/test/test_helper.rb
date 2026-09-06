ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/offline"

module TenantSetup
  extend ActiveSupport::Concern

  included do
    setup do
      @tenant = Tenant.create!(subdomain: "demo-#{SecureRandom.hex(4)}", name: "Demo")
      @other = Tenant.create!(subdomain: "acme-#{SecureRandom.hex(4)}", name: "Acme")
    end
  end

  def within(tenant = @tenant, &block)
    Tenant.switch(tenant, &block)
  end

  def create_actor(tenant = @tenant, nickname: "owner", password: "password", **attributes)
    within(tenant) do
      Actor.create!(nickname: nickname, password: password, **attributes)
    end
  end

  def create_client(tenant = @tenant, **attributes)
    within(tenant) do
      Client.create!(
        name: attributes.delete(:name) || "Probe",
        client_id: SecureRandom.uuid,
        redirect_uris: [ "https://probe.example.com/cb" ],
        token_endpoint_auth_method: "none",
        **attributes
      )
    end
  end

  def enable_otp(actor, tenant = @tenant)
    within(tenant) do
      actor.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      ROTP::TOTP.new(actor.reload.otp_secret)
    end
  end
end

module OidcFlow
  REDIRECT_URI = "https://probe.example.com/cb".freeze

  def host_for(tenant)
    "#{tenant.subdomain}.auth.test"
  end

  def origin_for(tenant)
    "http://#{host_for(tenant)}"
  end

  def issuer_for(tenant)
    Issuer.new(tenant, origin_for(tenant))
  end

  def register(tenant = @tenant, **metadata)
    host! host_for(tenant)

    post "/register",
         params: {
           client_name: "Probe",
           redirect_uris: [ REDIRECT_URI ],
           grant_types: [ "authorization_code", "refresh_token" ],
           scope: "openid profile email offline_access"
         }.merge(metadata).to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    JSON.parse(response.body)
  end

  def sign_in_as(actor, password: "password")
    post "/login", params: { event: "identify", identifier: actor.nickname }, as: :json
    post "/login", params: { event: "password", password: password }, as: :json
    JSON.parse(response.body)
  end

  def verifier
    @verifier ||= SecureRandom.urlsafe_base64(64)
  end

  def challenge(from = verifier)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(from), padding: false)
  end

  def authorize(client_id:, resource: nil, **params)
    query = {
      response_type: "code",
      client_id: client_id,
      redirect_uri: REDIRECT_URI,
      scope: "openid profile email",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }.merge(params).compact.to_a

    Array(resource).each { |value| query << [ "resource", value ] }

    get "/authorize?#{URI.encode_www_form(query)}"
    response
  end

  def auth_data
    raw = response.body[/data-auth="([^"]*)"/, 1]
    raw && JSON.parse(CGI.unescapeHTML(raw))
  end

  def current_rid
    auth_data&.dig("rid")
  end

  def login_forms
    response.body.scan(%r{<form[^>]*action="/login"[^>]*>.*?</form>}m)
  end

  def form_rids
    login_forms.map { |form| form[/name="rid"[^>]*value="([^"]*)"/, 1] }
  end

  def advance!(event, **updates)
    post "/login", params: { event: event, rid: current_rid, **updates }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")
    response
  end

  def consent!
    advance!("consent", approve: "yes")
  end

  def decline!
    advance!("decline")
  end

  def redirected
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  def code_from(location = response.location)
    Rack::Utils.parse_query(URI.parse(location).query)["code"]
  end

  def token(**params)
    body = params.compact.flat_map { |key, value| Array(value).map { |one| [ key.to_s, one.to_s ] } }

    post "/token",
         params: URI.encode_www_form(body),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    JSON.parse(response.body)
  end

  def claims_in(jwt, tenant = @tenant)
    JWT.decode(
      jwt, nil, true,
      algorithms: [ SigningKey::ALGORITHM ],
      jwks: issuer_for(tenant).jwks
    ).first
  end

  def awaiting_consent?
    !response.redirect? && auth_data&.dig("prompt") == "consent"
  end

  def awaiting_login?
    !response.redirect? && %w[setup identify first-factor second-factor backup-code].include?(auth_data&.dig("prompt"))
  end

  def authorized_code(actor:, registration:, resource: nil, scope: "openid profile email offline_access")
    sign_in_as(actor)
    authorize(client_id: registration["client_id"], scope: scope, resource: resource)
    consent! if awaiting_consent?
    code_from
  end

  def access_token_for(actor:, registration:, resource: nil, **params)
    code = authorized_code(actor: actor, registration: registration, resource: resource)

    token(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"],
      **params
    )
  end
end

class ActiveSupport::TestCase
  include TenantSetup

  setup { Rails.cache.clear }
end

class ActionDispatch::IntegrationTest
  include OidcFlow
end
