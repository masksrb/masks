require "socket"

module Federated
  extend ActiveSupport::Concern

  class Upstream
    attr_reader :port, :requests, :claims

    def initialize(key)
      @key = key
      @claims = {}
      @requests = []
      @lock = Mutex.new
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { serve }
    end

    def url(path = "")
      "http://127.0.0.1:#{port}#{path}"
    end

    def announce(claims)
      @lock.synchronize { @claims = claims }
    end

    def bodies_for(path)
      @lock.synchronize { @requests.select { |one| one[:path] == path }.map { |one| one[:body] } }
    end

    def stop
      @thread.kill
      @server.close
    rescue IOError
      nil
    end

    def jwk
      SigningKey.jwk_for(@key.public_key, "upstream-key")
    end

    private

      def payload_for(path)
        case path
        when "/.well-known/openid-configuration"
          {
            "issuer" => url,
            "authorization_endpoint" => url("/o/authorize"),
            "token_endpoint" => url("/o/token"),
            "userinfo_endpoint" => url("/o/userinfo"),
            "jwks_uri" => url("/o/jwks")
          }
        when "/borrowed/.well-known/openid-configuration"
          { "issuer" => "https://accounts.google.com" }
        when "/o/jwks" then { "keys" => [ jwk ] }
        when "/o/token" then { "access_token" => "upstream-access", "expires_in" => 3600, "id_token" => id_token }
        when "/o/userinfo" then @lock.synchronize { @claims.slice("sub", "email", "email_verified") }
        end
      end

      def id_token
        held = @lock.synchronize { @claims.dup }

        JWT.encode(
          { "iss" => url, "aud" => "upstream-client", "exp" => 5.minutes.from_now.to_i,
            "iat" => Time.current.to_i }.merge(held),
          @key, "RS256", kid: "upstream-key", typ: "JWT"
        )
      end

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
        length = 0

        while (header = socket.gets) && header.strip != ""
          length = header.split(":", 2).last.to_i if header.downcase.start_with?("content-length")
        end

        path = line.split(" ")[1].to_s.split("?").first
        body = length.positive? ? socket.read(length).to_s : ""

        @lock.synchronize { @requests << { path: path, body: Rack::Utils.parse_query(body) } }

        found = payload_for(path)
        payload = JSON.generate(found || { "error" => "not_found" })

        socket.print [
          "HTTP/1.1 #{found ? '200 OK' : '404 Not Found'}",
          "Content-Type: application/json",
          "Content-Length: #{payload.bytesize}",
          "Connection: close",
          "", payload
        ].join("\r\n")
      rescue Errno::EPIPE, IOError
        nil
      ensure
        socket.close rescue nil
      end
  end

  included do
    setup do
      @upstream = Upstream.new(OpenSSL::PKey::RSA.generate(2048))
      host! host_for(@tenant)
    end

    teardown { @upstream&.stop }
  end

  def create_provider(**attributes)
    within(@tenant) do
      Provider.create!(
        key: "acme",
        name: "Acme",
        issuer: @upstream.url,
        authorization_url: @upstream.url("/o/authorize"),
        token_url: @upstream.url("/o/token"),
        userinfo_url: @upstream.url("/o/userinfo"),
        jwks_uri: @upstream.url("/o/jwks"),
        client_id: "upstream-client",
        client_secret: "upstream-secret",
        signs_in: true,
        **attributes
      )
    end
  end

  def begin_sso(key: "acme", rid: nil)
    post "/login", params: { event: "provider", provider: key, rid: rid }.compact, as: :json

    body = JSON.parse(response.body)
    handed = body["redirectTo"]

    handed ? Rack::Utils.parse_query(URI.parse(handed).query).merge("body" => body) : body
  end

  def finish_sso(sub:, email:, verified: true, key: "acme", **overrides)
    handoff = overrides.delete(:handoff) || begin_sso(key: key)

    @upstream.announce(
      { "sub" => sub, "email" => email, "email_verified" => verified,
        "nonce" => handoff["nonce"] }.merge(overrides.stringify_keys)
    )

    get "/login/provider/#{key}/callback",
        params: { code: "upstream-code", state: handoff["state"] }

    handoff
  end

  def prove(password: "password")
    post "/login", params: { event: "password", password: password }, as: :json

    JSON.parse(response.body)
  end

  def refusals
    within(@tenant) do
      Event.where(action: Event::CONNECTION_REFUSED).map { |event| event.details["reason"].to_s }
    end
  end

  def signed_in_actor
    within(@tenant) { Session.live.order(created_at: :desc).first&.actor }
  end

  def warnings
    flash[:warnings] || JSON.parse(response.body)["warnings"] rescue []
  end
end
