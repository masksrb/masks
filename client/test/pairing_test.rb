require_relative "test_helper"

class PairingTest < ClientTest
  APP = "https://app.test".freeze

  def url(**overrides)
    Masks::Client::Pairing.url(
      "#{issuer.url}/",
      **{
        name: "Things",
        resource: "#{APP}/mcp",
        redirect_uris: [ "#{APP}/auth/callback" ],
        scope: %w[openid things:read],
        return_to: "#{APP}/setup/callback",
        state: "a-state"
      }.merge(overrides)
    )
  end

  def query(**overrides)
    URI.decode_www_form(URI.parse(url(**overrides)).query)
       .group_by(&:first)
       .transform_values { |pairs| pairs.map(&:last) }
  end

  def test_the_connect_url_is_built_without_fetching_discovery
    assert url.start_with?("#{issuer.url}/setup/connect?")
    assert_equal 0, issuer.count("/.well-known/openid-configuration")
  end

  def test_every_value_the_approval_screen_shows_travels_in_the_query
    held = query

    assert_equal [ "Things" ], held["client_name"]
    assert_equal [ "#{APP}/mcp" ], held["resource"]
    assert_equal [ "openid things:read" ], held["scope"]
    assert_equal [ "#{APP}/setup/callback" ], held["return_to"]
    assert_equal [ "a-state" ], held["state"]
  end

  def test_redirect_uris_repeat_rather_than_joining
    held = query(redirect_uris: [ "#{APP}/a", "#{APP}/b" ])

    assert_equal [ "#{APP}/a", "#{APP}/b" ], held["redirect_uris"]
  end

  def test_an_issuer_object_and_its_url_build_the_same_thing
    resolved = Masks::Client.issuer(issuer.url)

    assert_equal url, Masks::Client::Pairing.url(
      resolved,
      name: "Things",
      resource: "#{APP}/mcp",
      redirect_uris: [ "#{APP}/auth/callback" ],
      scope: %w[openid things:read],
      return_to: "#{APP}/setup/callback",
      state: "a-state"
    )
  end
end
