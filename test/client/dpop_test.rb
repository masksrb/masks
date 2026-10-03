require_relative "test_helper"

class DpopTest < ClientTest
  URL = "https://app.test/mcp".freeze

  def key
    @key ||= OpenSSL::PKey::EC.generate("prime256v1")
  end

  def jwk(signer = key)
    JWT::JWK.new(signer).export.transform_keys(&:to_s).slice("kty", "crv", "x", "y")
  end

  def jkt(signer = key)
    Masks::Client::Proof.thumbprint(jwk(signer))
  end

  def bound(signer = key)
    issuer.access_token("cnf" => { "jkt" => jkt(signer) })
  end

  def proof(token, signer: key, htm: "GET", htu: URL, iat: Time.now.to_i, jti: SecureRandom.uuid, ath: nil)
    claims = { "htm" => htm, "htu" => htu, "iat" => iat, "jti" => jti,
               "ath" => ath || Masks::Client::Proof.digest(token) }

    JWT.encode(claims, signer, "ES256", { "typ" => "dpop+jwt", "jwk" => jwk(signer) })
  end

  def guarded
    @guarded ||= resource
  end

  def presented(token, held = proof(token), method: "GET", url: URL)
    guarded.authenticate("DPoP #{token}", proof: held, method: method, url: url)
  end

  def refused(&block)
    assert_raises(Masks::Client::Unauthorized, &block)
  end

  def test_a_bound_token_with_a_matching_proof_becomes_claims
    token = bound

    assert_equal "actor-1", presented(token).subject
  end

  def test_a_bound_token_presented_as_bearer_is_refused
    error = refused { guarded.authenticate("Bearer #{bound}") }

    assert_match "bound to a key", error.description
  end

  def test_a_bound_token_without_a_proof_is_refused
    token = bound

    assert_equal "invalid_dpop_proof", refused { presented(token, nil) }.code
  end

  def test_a_proof_from_another_key_is_refused
    token = bound
    other = OpenSSL::PKey::EC.generate("prime256v1")

    assert_match "another key", refused { presented(token, proof(token, signer: other)) }.description
  end

  def test_a_proof_for_another_method_url_or_token_is_refused
    token = bound

    assert_match "another method", refused { presented(token, proof(token, htm: "POST")) }.description
    assert_match "another URL", refused { presented(token, proof(token, htu: "https://app.test/other")) }.description
    assert_match "another token", refused { presented(token, proof(token, ath: "wrong")) }.description
  end

  def test_the_query_does_not_count_toward_the_url
    token = bound

    assert presented(token, proof(token, htu: "#{URL}?a=1"), url: URL)
  end

  def test_a_stale_proof_is_refused
    token = bound

    assert_match "too long ago", refused { presented(token, proof(token, iat: Time.now.to_i - 300)) }.description
  end

  def test_a_proof_is_used_once
    token = bound
    held = proof(token)

    presented(token, held)

    assert_match "already been used", refused { presented(token, held) }.description
  end

  def test_an_unbound_token_presented_as_dpop_is_refused
    token = issuer.access_token

    assert_match "not bound", refused { presented(token) }.description
  end

  def test_the_metadata_names_the_proof_algorithms
    assert_includes resource.metadata["dpop_signing_alg_values_supported"], "ES256"
  end
end
