require "test_helper"
require "socket"

class ConnectionBrokerTest < ActionDispatch::IntegrationTest
  class FakeProvider
    attr_reader :port, :requests

    def initialize(responses)
      @responses = responses
      @requests = []
      @lock = Mutex.new
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { serve }
    end

    def url(path)
      "http://127.0.0.1:#{port}#{path}"
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
        length = 0

        while (header = socket.gets) && header.strip != ""
          length = header.split(":", 2).last.to_i if header.downcase.start_with?("content-length")
        end

        path = line.split(" ")[1].to_s.split("?").first
        body = length.positive? ? socket.read(length).to_s : ""

        @lock.synchronize { @requests << { path: path, body: Rack::Utils.parse_query(body) } }

        found = @responses[path]
        found = found.call if found.respond_to?(:call)
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

  GOOGLE_SCOPE = "masks:connections:google".freeze

  setup do
    @actor = create_actor(@tenant, nickname: "owner", email: "owner@example.com")
  end

  teardown { @upstream&.stop }

  def with_upstream(responses)
    @upstream = FakeProvider.new(responses)
    yield @upstream
  end

  def create_provider(upstream, key: "google", name: "Google", **attributes)
    within(@tenant) do
      Provider.create!(
        key: key,
        name: name,
        authorization_url: upstream.url("/o/authorize"),
        token_url: upstream.url("/o/token"),
        revocation_url: upstream.url("/o/revoke"),
        userinfo_url: upstream.url("/o/userinfo"),
        client_id: "upstream-client",
        client_secret: "upstream-secret",
        scopes: "https://www.googleapis.com/auth/drive.readonly",
        **attributes
      )
    end
  end

  def token_response(access_token: "upstream-access", refresh_token: "upstream-refresh", expires_in: 3600, scope: nil)
    {
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "expires_in" => expires_in,
      "scope" => scope
    }.compact
  end

  def identity(sub:, email:)
    { "sub" => sub, "email" => email }
  end

  def connect!(provider, sub:, email:, return_to: nil)
    host! host_for(@tenant)
    sign_in_as(@actor)

    post "/connections/#{provider.key}/start", params: { return_to: return_to }.compact

    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get "/connections/#{provider.key}/callback", params: { code: "upstream-code", state: state }

    state
  end

  def sequence(*values)
    index = -1
    lock = Mutex.new

    lambda do
      lock.synchronize do
        index += 1
        values[[ index, values.size - 1 ].min]
      end
    end
  end

  def bearer_for(actor: @actor, scope: "openid #{GOOGLE_SCOPE}")
    registration = within(@tenant) do
      client = create_client(@tenant, name: "uris")
      client.update!(
        allowed_scopes: "openid profile email offline_access #{GOOGLE_SCOPE}",
        approved_at: Time.current,
        redirect_uris: [ OidcFlow::REDIRECT_URI ]
      )
      { "client_id" => client.client_id }
    end

    reset!
    host! host_for(@tenant)

    code = authorized_code(actor: actor, registration: registration, scope: scope)

    issued = token(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"]
    )

    issued["access_token"]
  end

  def release(connection_id, bearer)
    post "/connections/token",
         params: { connection_id: connection_id },
         headers: { "HTTP_AUTHORIZATION" => "Bearer #{bearer}" }

    JSON.parse(response.body)
  end

  test "a connection is recorded and its upstream token released to a scoped bearer" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }

      assert_equal "google-1", connection.subject
      assert_equal "user@gmail.com", connection.label
      assert_equal @actor.id, connection.actor_id

      body = release(connection.uuid, bearer_for)

      assert_equal "upstream-access", body["access_token"]
      assert_equal "google", body.dig("connection", "provider")
    end
  end

  test "two accounts at one provider are two connections for one actor" do
    with_upstream(
      "/o/token" => -> { token_response },
      "/o/userinfo" => sequence(
        identity(sub: "google-1", email: "work@example.com"),
        identity(sub: "google-2", email: "personal@example.com")
      )
    ) do |upstream|
      provider = create_provider(upstream)

      connect!(provider, sub: "google-1", email: "work@example.com")
      connect!(provider, sub: "google-2", email: "personal@example.com")

      held = within(@tenant) { Connection.live.order(:subject).to_a }

      assert_equal %w[google-1 google-2], held.map(&:subject)
      assert_equal %w[work@example.com personal@example.com].sort, held.map(&:label).sort
      assert_equal [ @actor.id ], held.map(&:actor_id).uniq
    end
  end

  test "re-enrolling the same upstream account updates it rather than duplicating" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "renamed@example.com")
    ) do |upstream|
      provider = create_provider(upstream)

      connect!(provider, sub: "google-1", email: "renamed@example.com")
      connect!(provider, sub: "google-1", email: "renamed@example.com")

      assert_equal 1, within(@tenant) { Connection.live.count }
    end
  end

  test "a bearer without the provider's scope cannot release the connection" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }
      body = release(connection.uuid, bearer_for(scope: "openid"))

      assert_equal 403, response.status
      assert_equal "insufficient_scope", body["error"]
      assert_no_match(/upstream-access/, response.body)
    end
  end

  test "a scope for one provider does not release another provider's connection" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "gh-1", email: "user@example.com")
    ) do |upstream|
      github = create_provider(upstream, key: "github", name: "GitHub")
      connect!(github, sub: "gh-1", email: "user@example.com")

      connection = within(@tenant) { Connection.live.sole }
      body = release(connection.uuid, bearer_for)

      assert_equal "insufficient_scope", body["error"]
      assert_match "masks:connections:github", body["error_description"]
    end
  end

  test "another actor's connection is not found rather than refused" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }

      stranger = create_actor(@tenant, nickname: "stranger")

      body = release(connection.uuid, bearer_for(actor: stranger))

      assert_equal 404, response.status
      assert_equal "invalid_target", body["error"]
    end
  end

  test "a stale access token is refreshed before it is released" do
    with_upstream(
      "/o/token" => sequence(
        token_response(access_token: "first-access"),
        token_response(access_token: "second-access", refresh_token: nil)
      ),
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      within(@tenant) do
        Connection.live.sole.update!(access_token_expires_at: 1.minute.ago)
      end

      connection = within(@tenant) { Connection.live.sole }
      body = release(connection.uuid, bearer_for)

      assert_equal "second-access", body["access_token"]

      refreshes = upstream.bodies_for("/o/token").select { |one| one["grant_type"] == "refresh_token" }

      assert_equal 1, refreshes.size
      assert_equal "upstream-refresh", refreshes.first["refresh_token"],
                   "a refresh response without a refresh_token must not erase the one we hold"
    end
  end

  test "an upstream that refuses the refresh marks the connection revoked" do
    with_upstream(
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com"),
      "/o/token" => sequence(token_response, nil)
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      within(@tenant) do
        Connection.live.sole.update!(access_token_expires_at: 1.minute.ago)
      end

      connection = within(@tenant) { Connection.live.sole }
      body = release(connection.uuid, bearer_for)

      assert_equal "invalid_grant", body["error"]
      assert within(@tenant) { Connection.find_by(uuid: connection.uuid).revoked? },
             "a refusal upstream is how revocation at the other end is discovered"
    end
  end

  test "the refresh token never appears in any response" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }

      release(connection.uuid, bearer_for)
      assert_no_match(/upstream-refresh/, response.body)

      get "/connections", headers: { "HTTP_AUTHORIZATION" => "Bearer #{bearer_for}" }
      assert_no_match(/upstream-refresh/, response.body)
      assert_no_match(/upstream-access/, response.body)
    end
  end

  test "a connection scope may not be registered dynamically" do
    host! host_for(@tenant)

    registration = register(@tenant, scope: "openid #{GOOGLE_SCOPE}")

    assert_equal "invalid_client_metadata", registration["error"],
                 "open registration must not be able to ask for a connection scope"
  end

  test "a state this browser did not begin is refused" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)

      host! host_for(@tenant)
      sign_in_as(@actor)

      get "/connections/#{provider.key}/callback", params: { code: "upstream-code", state: "forged" }

      assert_equal 400, response.status
      assert_equal 0, within(@tenant) { Connection.count }
    end
  end

  test "a return_to no client claims is not redirected to" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com", return_to: "https://evil.example.com/take")

      assert_not response.redirect?,
                 "an unclaimed origin must not become a redirect target"
      assert_equal 200, response.status
    end
  end

  test "revoking a connection stops it releasing" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com"),
      "/o/revoke" => { "ok" => true }
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }

      delete "/connections/#{connection.uuid}"
      assert_equal 200, response.status

      body = release(connection.uuid, bearer_for)

      assert_equal "invalid_grant", body["error"]
      assert_equal 1, upstream.bodies_for("/o/revoke").size,
                   "revoking here must also revoke at the provider"
    end
  end

  test "one tenant cannot release another tenant's connection" do
    with_upstream(
      "/o/token" => token_response,
      "/o/userinfo" => identity(sub: "google-1", email: "user@gmail.com")
    ) do |upstream|
      provider = create_provider(upstream)
      connect!(provider, sub: "google-1", email: "user@gmail.com")

      connection = within(@tenant) { Connection.live.sole }

      assert_nil within(@other) { Connection.find_by(uuid: connection.uuid) },
                 "a connection must not be visible from another tenant"
    end
  end
end
