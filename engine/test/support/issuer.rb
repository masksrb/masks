require "socket"
require "json"
require "jwt"
require "securerandom"
require "openssl"
require "base64"

class TestIssuer
  ALGORITHM = "RS256".freeze

  class << self
    def current
      @current ||= new
    end
  end

  attr_reader :port, :registrations

  def initialize
    @keys = {}
    @codes = {}
    @approvals = {}
    @registrations = []
    @lock = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
  end

  def origin
    "http://127.0.0.1:#{port}"
  end

  def url_for(subdomain)
    "#{origin}/#{subdomain}"
  end

  def approve!(subdomain)
    token = SecureRandom.urlsafe_base64(24)

    @lock.synchronize { @approvals[token] = subdomain }
    token
  end

  def authorize!(location, scopes: %w[openid profile email catalog:read])
    query = URI.decode_www_form(URI.parse(location).query.to_s).each_with_object({}) do |(key, value), held|
      (held[key] ||= []) << value
    end
    code = SecureRandom.urlsafe_base64(24)

    @lock.synchronize do
      @codes[code] = {
        challenge: query.dig("code_challenge", 0),
        nonce: query.dig("nonce", 0),
        client_id: query.dig("client_id", 0),
        resource: query.dig("resource", 0),
        scopes: Array(scopes)
      }
    end

    { code: code, state: query.dig("state", 0), query: query }
  end

  def last_registration
    @lock.synchronize { @registrations.last }
  end

  def key_for(subdomain)
    @lock.synchronize do
      @keys[subdomain] ||= { key: OpenSSL::PKey::RSA.generate(2048), kid: SecureRandom.uuid }
    end
  end

  def mint(subdomain:, audience:, subject: "actor-1", scopes: [], expires_in: 3600,
           tenant: nil, **extra)
    held = key_for(subdomain)

    JWT.encode({
      "iss" => url_for(subdomain),
      "sub" => subject,
      "aud" => audience,
      "exp" => Time.now.to_i + expires_in,
      "iat" => Time.now.to_i,
      "jti" => SecureRandom.uuid,
      "scope" => Array(scopes).join(" "),
      "tenant" => tenant || { "uuid" => "uuid-#{subdomain}", "subdomain" => subdomain }
    }.merge(extra).compact, held[:key], ALGORITHM, { kid: held[:kid] })
  end

  private

    def serve
      loop do
        socket = @server.accept
        Thread.new { respond(socket) }
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def respond(socket)
      line = socket.gets.to_s
      headers = {}

      while (header = socket.gets) && header.strip != ""
        name, value = header.split(":", 2)
        headers[name.to_s.strip.downcase] = value.to_s.strip
      end

      method, path = line.split(" ")
      length = headers["content-length"].to_i
      payload = length.positive? ? socket.read(length).to_s : ""
      bearer = headers["authorization"].to_s.split(" ").last

      found = case method
      when "POST" then post_for(path.to_s, payload, bearer)
      else get_for(path.to_s, bearer)
      end

      body = JSON.generate(found || { "error" => "not_found" })
      status = if found.nil?
        "404 Not Found"
      elsif found["error"]
        "400 Bad Request"
      else
        "200 OK"
      end

      socket.print [
        "HTTP/1.1 #{status}",
        "Content-Type: application/json",
        "Content-Length: #{body.bytesize}",
        "Connection: close",
        "", body
      ].join("\r\n")
    rescue Errno::EPIPE, IOError
      nil
    ensure
      socket.close rescue nil
    end

    def get_for(path, bearer)
      case path
      when %r{\A/([^/]+)/\.well-known/openid-configuration\z} then discovery($1)
      when %r{\A/([^/]+)/\.well-known/jwks\.json\z} then jwks($1)
      when %r{\A/([^/]+)/userinfo\z} then userinfo($1, bearer)
      end
    end

    def post_for(path, payload, bearer)
      return registered($1, payload, bearer) if path =~ %r{\A/([^/]+)/register\z}
      return nil unless path =~ %r{\A/([^/]+)/token\z}

      subdomain = $1
      form = URI.decode_www_form(payload).to_h

      return refreshed(subdomain, form) if form["grant_type"] == "refresh_token"

      pending = @lock.synchronize { @codes.delete(form["code"]) }

      return { "error" => "invalid_grant" } if pending.nil?
      return { "error" => "invalid_grant" } unless verifies?(pending, form["code_verifier"])

      granted(subdomain, pending)
    end

    def verifies?(pending, verifier)
      return false if verifier.nil? || verifier.empty?

      Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(verifier), padding: false
      ) == pending[:challenge]
    end

    def granted(subdomain, pending)
      audience = pending[:resource] || "#{url_for(subdomain)}/mcp"

      {
        "access_token" => mint(subdomain: subdomain, scopes: pending[:scopes], audience: audience),
        "id_token" => mint(subdomain: subdomain, audience: pending[:client_id], scopes: [],
                           nonce: pending[:nonce], name: "Test Owner",
                           preferred_username: "owner", email: "owner@example.invalid",
                           email_verified: true),
        "refresh_token" => SecureRandom.urlsafe_base64(24),
        "token_type" => "Bearer",
        "scope" => Array(pending[:scopes]).join(" "),
        "expires_in" => 3600
      }
    end

    def refreshed(subdomain, form)
      return { "error" => "invalid_grant" } if form["refresh_token"].to_s.empty?

      {
        "access_token" => mint(subdomain: subdomain, scopes: %w[catalog:read],
                               audience: form["resource"] || "#{url_for(subdomain)}/mcp"),
        "refresh_token" => SecureRandom.urlsafe_base64(24),
        "token_type" => "Bearer",
        "scope" => "catalog:read",
        "expires_in" => 3600
      }
    end

    def registered(subdomain, payload, token)
      approved = @lock.synchronize { @approvals.delete(token) }

      return { "error" => "invalid_token" } unless approved == subdomain

      metadata = begin
        JSON.parse(payload)
      rescue JSON::ParserError
        {}
      end
      client_id = SecureRandom.uuid

      @lock.synchronize { @registrations << metadata }

      metadata.merge(
        "client_id" => client_id,
        "client_secret" => SecureRandom.urlsafe_base64(24),
        "registration_access_token" => SecureRandom.urlsafe_base64(24),
        "registration_client_uri" => "#{url_for(subdomain)}/register/#{client_id}"
      )
    end

    def userinfo(subdomain, bearer)
      return { "error" => "invalid_token" } if bearer.nil? || bearer.empty?

      {
        "sub" => "actor-1",
        "name" => "Test Owner",
        "preferred_username" => "owner",
        "email" => "owner@example.invalid",
        "email_verified" => true
      }
    end

    def discovery(subdomain)
      url = url_for(subdomain)

      {
        "issuer" => url,
        "authorization_endpoint" => "#{url}/authorize",
        "token_endpoint" => "#{url}/token",
        "userinfo_endpoint" => "#{url}/userinfo",
        "jwks_uri" => "#{url}/.well-known/jwks.json",
        "registration_endpoint" => "#{url}/register",
        "handshake_endpoint" => "#{url}/handshake",
        "revocation_endpoint" => "#{url}/revoke",
        "tenant" => { "uuid" => "uuid-#{subdomain}", "subdomain" => subdomain }
      }
    end

    def jwks(subdomain)
      held = key_for(subdomain)

      { "keys" => [ JWT::JWK.new(held[:key], { kid: held[:kid], use: "sig", alg: ALGORITHM }).export ] }
    end
end
