require_relative "test_helper"

class KeyTest < ClientTest
  def key
    @key ||= Masks::Client::Key.generate
  end

  def test_a_generated_key_publishes_only_its_public_half_named_by_its_thumbprint
    published = key.jwks["keys"].first

    assert_equal %w[alg crv kid kty use x y], published.keys.sort
    assert_equal key.thumbprint, published["kid"]
    assert_equal Masks::Client::Proof.thumbprint(published), key.thumbprint
    assert_equal [ "EC", "P-256", "ES256", "sig" ], published.values_at("kty", "crv", "alg", "use")
  end

  def test_a_key_comes_back_from_its_jwk_and_its_pem
    assert_equal key.thumbprint, Masks::Client::Key.parse(key.to_json).thumbprint
    assert_equal key.thumbprint, Masks::Client::Key.parse(key.to_h).thumbprint
    assert_equal key.thumbprint, Masks::Client::Key.parse(key.to_pem).thumbprint
    assert_equal key.thumbprint, Masks::Client::Key.from(key.private_key).thumbprint
  end

  def test_a_public_key_or_another_curve_or_rsa_is_refused
    assert_raises(ArgumentError) { Masks::Client::Key.parse(JSON.generate(key.public_jwk)) }
    assert_raises(ArgumentError) { Masks::Client::Key.new(OpenSSL::PKey::EC.generate("secp384r1")) }
    assert_raises(ArgumentError) { Masks::Client::Key.new(OpenSSL::PKey::RSA.generate(2048)) }
    assert_raises(ArgumentError) { Masks::Client::Key.parse("not a key") }
  end

  def test_inspecting_a_key_shows_its_thumbprint_and_nothing_private
    assert_equal "#<Masks::Client::Key #{key.thumbprint}>", key.inspect
    refute_includes key.inspect, key.to_h["d"]
  end

  def test_a_proof_passes_the_check_a_resource_makes
    proof = key.proof("get", "https://app.test/mcp?page=2#top", access_token: "the-token")

    checked = Masks::Client::Proof.new(proof, method: "GET", url: "https://app.test/mcp")
                                  .check!(access_token: "the-token", jkt: key.thumbprint)

    assert checked
  end

  def test_a_proof_names_the_method_and_url_without_query_or_fragment_and_carries_only_the_public_key
    proof = key.proof("post", "https://auth.test/token?x=1#y", nonce: "n-1")
    claims, header = JWT.decode(proof, key.private_key, true, algorithms: [ "ES256" ])

    assert_equal "dpop+jwt", header["typ"]
    assert_equal %w[crv kty x y], header["jwk"].keys.sort
    assert_equal [ "POST", "https://auth.test/token", "n-1" ], claims.values_at("htm", "htu", "nonce")
    assert_nil claims["ath"]
    refute_empty claims["jti"]
    assert_in_delta Time.now.to_i, claims["iat"], 2
  end

  def test_every_proof_carries_a_new_jti
    claims = 2.times.map { JWT.decode(key.proof("GET", "https://app.test/"), nil, false).first["jti"] }

    assert_equal 2, claims.uniq.size
  end
end
