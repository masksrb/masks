class AuthorizationCode < Token
  def self.lifetime
    10.minutes
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
