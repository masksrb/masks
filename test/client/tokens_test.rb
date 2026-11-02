require_relative "test_helper"

class TokensTest < Minitest::Test
  CONTRACT = JSON.parse(File.read(File.expand_path("../contract/tokens.json", __dir__)))

  def setup
    Masks::Client.registry.clear!
    @issuer = FakeIssuer.new
    @issuer.override("/.well-known/openid-configuration", placed(CONTRACT["discovery"]))
    @issuer.override("/.well-known/jwks.json", CONTRACT["jwks"])
  end

  def teardown
    @issuer.stop
    Masks::Client.registry.clear!
  end

  def test_every_token_in_the_contract_ends_as_the_contract_says
    CONTRACT["cases"].each do |held|
      token = signed(held)

      if held["outcome"] == "ok"
        verify(held, token)
      else
        wanted = Masks::Client.failure(held["outcome"]["failure"], *placed(held["outcome"].fetch("values", [])))
        error = assert_raises(Masks::Client::InvalidToken, held["name"]) { verify(held, token) }

        assert_equal wanted, [ error.code, error.description ], held["name"]
      end
    end
  end

  private

    def names
      { "issuer" => @issuer.url, "client_id" => CONTRACT["client_id"], "resource" => CONTRACT["resource"] }
    end

    def placed(value)
      case value
      when String then names.reduce(value) { |text, (name, held)| text.gsub("{#{name}}", held) }
      when Array then value.map { |held| placed(held) }
      when Hash then value.transform_values { |held| placed(held) }
      else value
      end
    end

    def merged(base, overrides)
      Hash(overrides).reduce(base.dup) do |held, (name, value)|
        value.nil? ? held.except(name) : held.merge(name => value)
      end
    end

    def timed(claims)
      now = Time.now.to_i

      claims.to_h { |name, value| [ name, CONTRACT["times"].include?(name) && value.is_a?(Integer) ? value + now : value ] }
    end

    def encoded(value)
      Base64.urlsafe_encode64(JSON.generate(value), padding: false)
    end

    def signed(held)
      return held["raw"] if held.key?("raw")

      base = CONTRACT["tokens"][held["token"]]
      header = merged(base["header"], held["header"])
      claims = timed(placed(merged(base["claims"], held["claims"])))
      key = held.fetch("key", "signing")

      return "#{encoded(header)}.#{encoded(claims)}." if key == "none"

      signer = key == "secret" ? CONTRACT["secret"] : JWT::JWK.import(CONTRACT["keys"][key]).signing_key

      JWT.encode(claims, signer, header["alg"], header.except("alg"))
    end

    def verify(held, token)
      expecting = CONTRACT["expecting"].merge(held.fetch("expecting", {}))

      case held["token"]
      when "access"
        Masks::Client::Resource.new(issuer: @issuer.url, url: CONTRACT["resource"]).authenticate("Bearer #{token}")
      when "id"
        Masks::Client::IdToken.verify(
          token, issuer: @issuer.url, client_id: CONTRACT["client_id"],
          nonce: expecting["nonce"], access_token: expecting["access_token"],
          max_age: (expecting["max_age"] if expecting["max_age"].positive?)
        )
      when "logout"
        Masks::Client::Logout.verify(token, issuer: @issuer.url, audience: CONTRACT["client_id"])
      end
    end
end
