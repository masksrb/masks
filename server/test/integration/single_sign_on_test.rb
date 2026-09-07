require "test_helper"
require "socket"

class SingleSignOnTest < ActionDispatch::IntegrationTest
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

  setup do
    @upstream = Upstream.new(OpenSSL::PKey::RSA.generate(2048))
    host! host_for(@tenant)
  end

  teardown { @upstream&.stop }

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

  test "a confirmed address signs into the account that already holds it" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_equal actor.id, signed_in_actor&.id

    within(@tenant) do
      connection = Connection.live.find_by(subject: "upstream-1")

      assert_equal actor.id, connection.actor_id
      assert connection.signed_in_at.present?
      assert connection.email_verified
    end
  end

  test "a second sign-in reuses the connection rather than matching on email again" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")
    within(@tenant) { actor.update!(email: "moved@acme.test") }

    reset!
    host! host_for(@tenant)
    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_equal actor.id, signed_in_actor&.id
    assert_equal 1, within(@tenant) { Connection.live.count }
  end

  test "a revoked connection is taken up again rather than refused" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "upstream-1", email: "ada@acme.test")
    within(@tenant) { Connection.find_by(subject: "upstream-1").revoke!(upstream: false) }

    reset!
    host! host_for(@tenant)
    finish_sso(sub: "upstream-1", email: "ada@acme.test")

    assert_equal actor.id, signed_in_actor&.id
    assert_equal 1, within(@tenant) { Connection.count }
    assert within(@tenant) { Connection.find_by(subject: "upstream-1").revoked_at.nil? }
  end

  test "an unconfirmed address never reaches the account that holds it" do
    create_provider(provisions: true)
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }

    finish_sso(sub: "intruder", email: "ada@acme.test", verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an empty instance is set up locally, never over sso" do
    create_provider(provisions: true)

    finish_sso(sub: "upstream-0", email: "first@acme.test")

    assert_nil signed_in_actor
    assert_equal 0, within(@tenant) { Actor.count }

    get "/login"

    assert_equal "setup", auth_data["prompt"]
    assert_nil auth_data["providers"]
  end

  test "a provider that does not provision refuses somebody with no account" do
    create_provider
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-9", email: "nobody@acme.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
    assert within(@tenant) { Event.exists?(action: Event::CONNECTION_REFUSED) }
  end

  test "a provider that provisions creates the account and signs it in" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-2", email: "grace@acme.test", name: "Grace Hopper")

    actor = signed_in_actor

    assert actor, refusals.join("; ")
    assert_equal "grace", actor.nickname
    assert_equal "grace@acme.test", actor.email
    assert_equal "Grace Hopper", actor.name
    assert actor.email_verified_at.present?
    assert actor.activated?
    assert_equal Scopes::STANDARD.sort, actor.scope_list.sort
    assert within(@tenant) { Event.exists?(action: Event::ACTOR_PROVISIONED) }
  end

  test "a provisioned username steps aside when the obvious one is taken" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "grace", email: "someone@elsewhere.test")

    finish_sso(sub: "upstream-3", email: "grace@acme.test")

    assert_equal "grace2", signed_in_actor&.nickname
  end

  test "an email domain outside the list is refused" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-4", email: "someone@evil.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an identity carrying no address is refused when the list is set" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-11", email: nil, verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "an unconfirmed address inside the list is refused" do
    create_provider(provisions: true, email_domains: "acme.test")
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-12", email: "someone@acme.test", verified: false)

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "a provisioned account holds no address the provider did not confirm" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "upstream-13", email: "hopeful@acme.test", verified: false)

    actor = signed_in_actor

    assert actor, refusals.join("; ")
    assert_nil actor.email
    assert_nil actor.email_verified_at
  end

  test "an unconfirmed address cannot lie in wait for the person it names" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    finish_sso(sub: "intruder", email: "ada@acme.test", verified: false)

    planted = signed_in_actor

    assert planted, refusals.join("; ")

    reset!
    host! host_for(@tenant)

    finish_sso(sub: "ada", email: "ada@acme.test", verified: true)

    within(@tenant) do
      arrived = Connection.live.find_by(subject: "ada")

      assert arrived, refusals.join("; ")
      assert_not_equal planted.id, arrived.actor_id
      assert_equal "ada@acme.test", arrived.actor.email
    end
  end

  test "a confirmed address stays out of an active account that never confirmed it" do
    create_provider
    create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

    finish_sso(sub: "upstream-14", email: "ada@acme.test")

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "a confirmed address still takes up an invitation that is waiting" do
    create_provider
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    invited = within(@tenant) { Actor.create!(nickname: "ada", email: "ada@acme.test") }

    finish_sso(sub: "upstream-15", email: "ada@acme.test")

    assert_equal invited.id, signed_in_actor&.id
  end

  test "a state from another browser is refused" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso
    @upstream.announce(
      { "sub" => "upstream-5", "email" => "x@acme.test", "email_verified" => true,
        "nonce" => handoff["nonce"] }
    )

    get "/login/provider/acme/callback", params: { code: "upstream-code", state: "not-the-state" }

    assert_nil signed_in_actor
  end

  test "an id_token minted for another sign-in is refused" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso
    @upstream.announce(
      { "sub" => "upstream-6", "email" => "y@acme.test", "email_verified" => true,
        "nonce" => "a nonce from somewhere else" }
    )

    get "/login/provider/acme/callback", params: { code: "upstream-code", state: handoff["state"] }

    assert_nil signed_in_actor
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "the handoff carries pkce and a nonce, and redeems with the verifier" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")

    handoff = begin_sso

    assert_equal "S256", handoff["code_challenge_method"]
    assert handoff["code_challenge"].present?
    assert handoff["nonce"].present?
    assert_includes handoff["scope"].split, "openid"

    finish_sso(sub: "upstream-7", email: "z@acme.test", handoff: handoff)

    sent = @upstream.bodies_for("/o/token").last
    digest = Base64.urlsafe_encode64(
      OpenSSL::Digest::SHA256.digest(sent["code_verifier"].to_s), padding: false
    )

    assert_equal handoff["code_challenge"], digest
  end

  test "a provider that only brokers connections signs nobody in" do
    create_provider(signs_in: false, issuer: nil)

    body = begin_sso

    assert_nil body["redirectTo"]
    assert_nil body["providers"]
    assert_nil signed_in_actor
  end

  test "the sign-in page offers the providers that sign people in" do
    create_provider
    create_provider(key: "quiet", name: "Quiet", signs_in: false, issuer: nil)
    create_actor(@tenant, nickname: "ada", email: "ada@acme.test")

    get "/login"

    assert_response :success
    assert_equal [ { "key" => "acme", "name" => "Acme" } ], auth_data["providers"]
    assert_match "Continue with Acme", response.body
  end

  test "a provider sign-in is one factor, not two" do
    create_provider
    actor = create_actor(@tenant, nickname: "ada", email: "ada@acme.test")
    within(@tenant) { actor.update!(email_verified_at: Time.current) }
    enable_otp(actor)

    finish_sso(sub: "upstream-8", email: "ada@acme.test")

    assert_nil signed_in_actor

    get "/login"

    assert_equal "second-factor", auth_data["prompt"]
  end

  test "an authorize request survives the trip to the provider and back" do
    create_provider(provisions: true)
    create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
    registration = register(@tenant)

    authorize(client_id: registration["client_id"])

    handoff = begin_sso(rid: current_rid)

    assert handoff["state"].present?

    finish_sso(sub: "upstream-10", email: "roundtrip@acme.test", handoff: handoff)

    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert_equal "consent", auth_data["prompt"]
  end

  test "scopes handed to a provisioned account may not be privileged" do
    provider = create_provider(provisions: true)

    within(@tenant) do
      provider.signup_scopes = "openid masks:manage"

      assert_not provider.valid?
      assert_match(/masks:manage/, provider.errors.full_messages.join)
    end
  end

  test "an issuer that answers for somebody else is not trusted" do
    within(@tenant) do
      assert_raises(Provider::Untrusted) { Provider.discover(@upstream.url("/borrowed")) }
    end
  end

  test "discovery reads the endpoints an issuer publishes" do
    within(@tenant) do
      document = Provider.discover(@upstream.url)

      assert_equal @upstream.url("/o/token"), document["token_endpoint"]
      assert_equal @upstream.url("/o/jwks"), document["jwks_uri"]
    end
  end
end
