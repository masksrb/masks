class AuthorizationCode < Token
  def self.lifetime
    10.minutes
  end

  # A code presented twice is evidence the first presentation may not have been
  # the client's. OIDC Core 3.1.3.2 says the tokens issued from it SHOULD go
  # with it — revoking the code alone leaves the interceptor holding the thing
  # the code was only ever a means to.
  def revoke_issued!
    children.sum(&:revoke!)
  end

  def pkce?
    code_challenge.present?
  end

  def verifies?(verifier)
    return !pkce? if verifier.blank?
    return false unless pkce?

    case code_challenge_method
    when "S256"
      expected = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(verifier.to_s), padding: false
      )
      ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
    else
      false
    end
  end
end
