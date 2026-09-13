class ExchangePolicy < Policy
  checks :client_may_exchange,
         :token_types_are_supported,
         :subject_token_is_live,
         :scopes_only_narrow,
         :audience_only_narrows,
         :lifetime_only_shortens,
         :upstream_is_asked_for_plainly,
         :subject_token_was_issued_to_this_client,
         :client_is_approved,
         :connection_is_named,
         :connection_belongs_to_the_subject,
         :provider_still_delegates,
         :subject_token_carries_the_delegation,
         :delegation_is_live

  delegate :client, :claims, :subject_access_token, :subject_token_type,
           :requested_token_type, :requested_scopes, :requested_audience,
           :requested_lifetime, :named_audience, :upstream?, :connection, :delegation, to: :subject

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

      unless Exchange::REQUESTED_TOKEN_TYPES.include?(requested_token_type)
        deny!("invalid_request", "requested_token_type must be #{Exchange::REQUESTED_TOKEN_TYPES.join(' or ')}")
      end

      if named_audience.any? && !upstream?
        deny!("invalid_target", "audience names a connection, which only an upstream token is released for")
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

    def upstream_is_asked_for_plainly
      return unless upstream?

      if requested_scopes.any? || requested_audience.any? || requested_lifetime
        deny!("invalid_request", "an upstream token is released as the connection holds it, without scope, resource or lifetime")
      end
    end

    def subject_token_was_issued_to_this_client
      return unless upstream?

      deny!("invalid_grant", "subject_token was issued to another client") unless subject_access_token.client_id == client.id
    end

    def client_is_approved
      return unless upstream?

      deny!("unauthorized_client", "only an approved client can be released somebody's account elsewhere") unless client.approved?
    end

    def connection_is_named
      return unless upstream?

      deny!("invalid_target", "audience has to name exactly one connection") if connection.nil?
    end

    def connection_belongs_to_the_subject
      return unless upstream?

      if connection.revoked? || connection.actor_id != subject_access_token.actor_id
        deny!("invalid_grant", "that connection is not live for the person this token speaks for")
      end
    end

    def provider_still_delegates
      return unless upstream?

      deny!("invalid_grant", "#{connection.provider.name} no longer lets applications use it") unless connection.provider.delegating?
    end

    def subject_token_carries_the_delegation
      return unless upstream?

      scope = connection.provider.delegation_scope

      deny!("insufficient_scope", "subject_token does not carry #{scope}") unless subject_access_token.scope_list.include?(scope)
    end

    def delegation_is_live
      return unless upstream?

      deny!("invalid_grant", "#{subject_access_token.actor&.identifier || 'that person'} has not let this client use that connection") if delegation.nil?
    end
end
