$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "socket"
require "masks/client"

class FakeIssuer
  ALGORITHM = "RS256".freeze

  attr_reader :key, :kid, :port, :requests

  def initialize(tenant: { "uuid" => "t-1", "subdomain" => "jons", "name" => "Jons" })
    @key = OpenSSL::PKey::RSA.generate(2048)
    @kid = SecureRandom.uuid
    @tenant = tenant
    @requests = Hash.new(0)
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
      "revocation_endpoint" => "#{url}/revoke"
    }
  end

  def sign(claims, kid: self.kid, key: self.key)
    JWT.encode(claims, key, ALGORITHM, { kid: kid })
  end

  def access_token(subject: "actor-1", scope: "things:read things:write",
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
      while (header = socket.gets) && header.strip != ""
      end

      path = line.split(" ")[1].to_s
      @lock.synchronize { @requests[path] += 1 }

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

  def resource(url: "https://app.test/mcp", scopes: %w[things:read things:write resources:command])
    Masks::Client::Resource.new(issuer: issuer.url, url: url, scopes: scopes)
  end
end
