require_relative "test_helper"

class ConfigurationTest < EngineTest
  test "every value resolves against the request, so one host serves many tenants" do
    Masks::Rails.config.issuer = ->(request) { "https://#{request.host.split('.').first}.auth.test" }

    assert_equal "https://demo.auth.test", config.issuer_for(request_for("demo.app.test"))
    assert_equal "https://acme.auth.test", config.issuer_for(request_for("acme.app.test"))
  end

  test "a plain value is accepted where a callable would be" do
    Masks::Rails.config.issuer = "https://one.auth.test"

    assert_equal "https://one.auth.test", config.issuer_for(request_for(HOST))
  end

  test "an unset issuer refuses rather than building a url out of nothing" do
    Masks::Rails.config.issuer = nil

    assert_raises(Masks::Rails::Configuration::Unconfigured) do
      config.issuer_for(request_for(HOST))
    end
  end

  test "redirect_uri defaults to the callback on the host that was asked" do
    assert_equal "http://demo.app.test/auth/callback",
                 config.redirect_uri_for(request_for("demo.app.test"))
  end

  test "return_to is derived from the redirect_uri, so the two cannot disagree" do
    configure!(redirect_uri: ->(_request) { "https://public.example/auth/callback" })

    assert_equal "https://public.example/auth/handshake/callback",
                 config.return_to_for(request_for(HOST))
  end

  test "the origin of the redirect_uri is the origin of the return address, port included" do
    configure!(redirect_uri: ->(_request) { "http://public.example:4242/auth/callback" })

    redirect = URI.parse(config.redirect_uri_for(request_for(HOST)))
    returned = URI.parse(config.return_to_for(request_for(HOST)))

    assert_equal [ redirect.scheme, redirect.host, redirect.port ],
                 [ returned.scheme, returned.host, returned.port ]
  end

  test "a default port is left off the return address" do
    configure!(redirect_uri: ->(_request) { "https://public.example/auth/callback" })

    refute_includes config.return_to_for(request_for(HOST)), ":443"
  end

  test "configured? is what tells never connected from wrongly configured" do
    refute config.configured?(request_for(HOST))

    connect!

    assert config.configured?(request_for(HOST))
  end

  test "credentials with a blank client_id are not credentials" do
    configure!(credentials: ->(_request) { { client_id: "", client_secret: "s" } })

    refute config.configured?(request_for(HOST))
  end

  test "credentials may arrive with symbol or string keys" do
    configure!(credentials: ->(_request) { { "client_id" => "a", "client_secret" => "b" } })

    assert_equal "a", config.client_id_for(request_for(HOST))
    assert_equal "b", config.client_secret_for(request_for(HOST))
  end

  test "a session cannot be built for an app that has never shaken hands" do
    error = assert_raises(Masks::Rails::Configuration::Unconfigured) do
      config.session_for(request_for(HOST))
    end

    assert_includes error.message, "has not shaken hands"
  end

  test "an app that wrote no store still gets a working handshake" do
    held = Pathname.new(Dir.mktmpdir).join("masks.json")

    configure!(store: nil, credentials: nil)
    config.credentials_path = held

    registration = Struct.new(:client_id, :client_secret, :access_token, :uri)
                         .new("cid", "csec", "rat", "https://auth.test/register/cid")

    config.store!(request_for(HOST), registration)

    assert_equal "cid", config.client_id_for(request_for(HOST))
    assert_equal "csec", config.client_secret_for(request_for(HOST))
    assert_equal "600", format("%o", held.stat.mode & 0o777)
    assert_equal "cid", JSON.parse(held.read)["client_id"]
  ensure
    config.credentials_path = nil
    config.instance_variable_set(:@default_credentials, nil)
  end

  test "an app with no credentials file is simply unconnected" do
    configure!(store: nil, credentials: nil)
    config.credentials_path = Pathname.new(Dir.mktmpdir).join("absent.json")

    assert_equal false, config.configured?(request_for(HOST))
  ensure
    config.credentials_path = nil
    config.instance_variable_set(:@default_credentials, nil)
  end

  test "the name falls back to the application rather than being required" do
    configure!(name: nil)

    assert_equal "Dummy", config.name_for(request_for(HOST))
  end

  test "the handshake asks for exactly what the engine resolved" do
    handshake = config.handshake_for(request_for(HOST))

    assert_equal "#{origin}/mcp", handshake.resource
    assert_equal [ "#{origin}/auth/callback" ], handshake.redirect_uris
    assert_equal "#{origin}/auth/handshake/callback", handshake.return_to
    assert_includes handshake.scope, "catalog:read"
  end

  test "a handshake with no resource refuses, because that is the one the consumer owns" do
    configure!(resource: nil)

    assert_raises(Masks::Rails::Configuration::Unconfigured) do
      config.handshake_for(request_for(HOST))
    end
  end

  test "a resource server needs a resource too" do
    configure!(resource: nil)

    assert_raises(Masks::Rails::Configuration::Unconfigured) do
      config.resource_server_for(request_for(HOST))
    end
  end

  test "without a namespace the handshake asks for exactly what a sign-in does" do
    Masks::Rails.config.namespace = nil
    Masks::Rails.config.scope = %w[openid profile email offline_access uris:catalog:read]

    assert_equal %w[openid profile email offline_access uris:catalog:read],
                 config.approved_scope
  end

  test "a namespace collapses the scopes beneath it and keeps the rest" do
    Masks::Rails.config.namespace = "uris:"
    Masks::Rails.config.scope =
      %w[openid profile email offline_access uris:catalog:read uris:settings:write]

    assert_equal %w[openid profile email offline_access uris:], config.approved_scope
  end

  test "the handshake carries the namespace, so a new capability needs no approval" do
    Masks::Rails.config.namespace = "uris:"
    Masks::Rails.config.scope = %w[openid uris:catalog:read]

    handshake = config.handshake_for(request_for(HOST))

    assert_equal %w[openid uris:], handshake.scope
  end

  private

    def config
      Masks::Rails.config
    end

    def origin
      "http://#{HOST}"
    end

    def request_for(host)
      ActionDispatch::Request.new(
        Rack::MockRequest.env_for("http://#{host}/", "HTTP_HOST" => host)
      )
    end
end
