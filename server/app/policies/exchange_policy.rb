class ExchangePolicy < Policy
  checks :client_may_exchange,
         :token_types_are_supported,
         :subject_token_is_live,
         :scopes_only_narrow,
         :audience_only_narrows,
         :lifetime_only_shortens

  delegate :client, :claims, :subject_access_token, :subject_token_type,
           :requested_token_type, :requested_scopes, :requested_audience,
           :requested_lifetime, to: :subject

  private

    def client_may_exchange
      unless client.grants?(Exchange::GRANT_TYPE)
        deny!("unauthorized_client", "this client is not registered for token exchange")
      end
    end

    def token_types_are_supported
      unless Exchange::TOKEN_TYPES.include?(subject_token_type)
        deny!("invalid_request", "subject_token_type must be #{Exchange::ACCESS_TOKEN}")
      end

      unless Exchange::TOKEN_TYPES.include?(requested_token_type)
        deny!("invalid_request", "requested_token_type must be #{Exchange::ACCESS_TOKEN}")
      end
    end

    def subject_token_is_live
      deny!("invalid_grant", "subject_token could not be verified") if claims.nil?
      deny!("invalid_grant", "subject_token has been revoked or has expired") if subject_access_token.nil?
    end

    def scopes_only_narrow
      widened = requested_scopes - subject_access_token.scope_list

      if widened.any?
        deny!("invalid_scope",
              "an exchange cannot widen scope: #{widened.join(', ')} is not carried by the subject token")
      end
    end

    def audience_only_narrows
      return if subject_access_token.audience.empty?

      widened = requested_audience - subject_access_token.audience

      if widened.any?
        deny!("invalid_target",
              "an exchange cannot widen audience: #{widened.join(', ')} is not carried by the subject token")
      end
    end

    def lifetime_only_shortens
      return if requested_lifetime.nil?

      deny!("invalid_request", "requested lifetime must be positive") unless requested_lifetime.positive?
    end
end
