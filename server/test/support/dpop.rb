module DpopProofs
  def dpop_key
    @dpop_key ||= OpenSSL::PKey::EC.generate("prime256v1")
  end

  def dpop_jwk(key = dpop_key)
    JWT::JWK.new(key).export
  end

  def dpop_jkt(key = dpop_key)
    Proof.thumbprint(dpop_jwk(key).transform_keys(&:to_s))
  end

  def dpop_proof(method:, url:, key: dpop_key, access_token: nil, **claims)
    payload = {
      "jti" => SecureRandom.uuid,
      "htm" => method.to_s.upcase,
      "htu" => url,
      "iat" => Time.current.to_i
    }

    payload["ath"] = Proof.digest(access_token) if access_token

    JWT.encode(
      payload.merge(claims.transform_keys(&:to_s)),
      key, "ES256",
      { "typ" => Proof::TYPE, "jwk" => dpop_jwk(key) }
    )
  end

  def with_dpop(method:, url:, key: dpop_key, access_token: nil, **claims)
    { "HTTP_DPOP" => dpop_proof(method: method, url: url, key: key, access_token: access_token, **claims) }
  end
end
