$LOAD_PATH.unshift File.expand_path("../../client/lib", __dir__)

require "minitest/autorun"
require_relative "../support/offline"
require "socket"
require "masks/client"

class FakeIssuer
  ALGORITHM = "RS256".freeze

  attr_reader :key, :kid, :port, :requests, :received

  def initialize(tenant: { "uuid" => "t-1", "subdomain" => "demo", "name" => "Demo" })
    @key = OpenSSL::PKey::RSA.generate(2048)
    @kid = SecureRandom.uuid
    @tenant = tenant
    @requests = Hash.new(0)
    @received = []
    @lock = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @overrides = {}
    @thread = Thread.new { serve }
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  def stop
    @thread.kill
    @server.close
  rescue IOError
    nil
  end

  def count(path)
    @lock.synchronize { @requests[path] }
  end

  def last(path)
    @lock.synchronize { @received.reverse.find { |held| held[:path] == path } }
  end

  def override(path, body)
    @overrides[path] = body
  end

  def jwks
    { "keys" => [ public_jwk ] }
  end

  def public_jwk
    JWT::JWK.new(key, { kid: kid, use: "sig", alg: ALGORITHM }).export
  end

  def discovery
    {
      "issuer" => url,
      "tenant" => @tenant,
      "authorization_endpoint" => "#{url}/authorize",
      "token_endpoint" => "#{url}/token",
      "userinfo_endpoint" => "#{url}/userinfo",
      "jwks_uri" => "#{url}/.well-known/jwks.json",
      "registration_endpoint" => "#{url}/register",
      "handshake_endpoint" => "#{url}/handshake",
      "revocation_endpoint" => "#{url}/revoke",
      "introspection_endpoint" => "#{url}/introspect"
    }
  end

  def sign(claims, kid: self.kid, key: self.key)
    JWT.encode(claims, key, ALGORITHM, { kid: kid })
  end

  def access_token(subject: "actor-1", scope: "uris:catalog:read uris:catalog:write",
                   audience: "https://app.test/mcp", expires_in: 3600, **extra)
    sign({
      "iss" => url,
      "sub" => subject,
      "aud" => audience,
      "exp" => Time.now.to_i + expires_in,
      "iat" => Time.now.to_i,
      "jti" => SecureRandom.uuid,
      "scope" => scope,
      "tenant" => @tenant
    }.merge(extra))
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
      raw = length.positive? ? socket.read(length).to_s : ""

      @lock.synchronize do
        @requests[path] += 1
        @received << { method: method, path: path, headers: headers, body: parse(raw) }
      end

      found = body_for(path)
      body = JSON.generate(found || { "error" => "not_found" })

      socket.print [
        "HTTP/1.1 #{found ? '200 OK' : '404 Not Found'}",
        "Content-Type: application/json",
        "Content-Length: #{body.bytesize}",
        "Connection: close",
        "", body
      ].join("\r\n")
    ensure
      socket.close rescue nil
    end

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      URI.decode_www_form(raw).each_with_object({}) { |(name, value), held| held[name] = value }
    rescue StandardError
      {}
    end

    def body_for(path)
      return @overrides[path] if @overrides.key?(path)

      case path
      when "/.well-known/openid-configuration" then discovery
      when "/.well-known/jwks.json" then jwks
      end
    end
end

class ClientTest < Minitest::Test
  def setup
    Masks::Client.registry.clear!
    @issuer = FakeIssuer.new
  end

  def teardown
    @issuer.stop
    Masks::Client.registry.clear!
  end

  attr_reader :issuer

  def resource(url: "https://app.test/mcp", scopes: %w[uris:catalog:read uris:catalog:write resources:command])
    Masks::Client::Resource.new(issuer: issuer.url, url: url, scopes: scopes)
  end
end
