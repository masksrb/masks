class ExchangePolicy < Policy
  checks :client_may_exchange,
         :token_types_are_supported,
         :subject_token_is_live,
         :id_token_belongs_to_the_client,
         :actor_token_is_held,
         :scopes_only_narrow,
         :audience_only_narrows,
         :lifetime_only_shortens,
         :upstream_is_releasable

  delegate :client, :subject, :acting, :actor, :subject_token_type, :actor_token, :actor_token_type,
           :requested_token_type, :requested_scopes, :requested_audience, :available_scopes, :available_audience,
           :requested_lifetime, :named_audience, :upstream?, :connection, :delegation, to: :exchange

  private

    def exchange
      @subject
    end

    def client_may_exchange
      unless client.grants?(Exchange::GRANT_TYPE)
        deny!("unauthorized_client", "this client is not registered for token exchange")
      end
    end

    def token_types_are_supported
      unless Exchange::TOKEN_TYPES.include?(subject_token_type)
        deny!("invalid_request", "subject_token_type must be #{Exchange::TOKEN_TYPES.join(' or ')}")
      end

      if actor_token && !Exchange::TOKEN_TYPES.include?(actor_token_type.to_s)
        deny!("invalid_request", "actor_token_type must be #{Exchange::TOKEN_TYPES.join(' or ')}")
      end

      deny!("invalid_request", "actor_token_type is only sent beside an actor_token") if actor_token_type && actor_token.nil?

      unless Exchange::REQUESTED_TOKEN_TYPES.include?(requested_token_type)
        deny!("invalid_request", "requested_token_type must be #{Exchange::REQUESTED_TOKEN_TYPES.join(' or ')}")
      end

      if named_audience.any? && !upstream?
        deny!("invalid_target", "audience names a connection, which only an upstream token is released for")
      end

      if upstream? && subject_token_type != Exchange::ACCESS_TOKEN
        deny!("invalid_request", "an upstream token is only released for an access token")
      end
    end

    def subject_token_is_live
      deny!("invalid_grant", "subject_token could not be verified") if subject.nil?
      deny!("invalid_grant", "subject_token has been revoked or has expired") unless subject.live?
    end

    def id_token_belongs_to_the_client
      return unless subject.id_token?

      deny!("invalid_grant", "an id token is exchanged only by the client it was issued to") unless subject.held_by?(client)
    end

    def actor_token_is_held
      return if actor_token.nil?

      deny!("invalid_grant", "actor_token could not be verified") if acting.nil?
      deny!("invalid_grant", "actor_token has been revoked or has expired") unless acting.live?
      deny!("invalid_grant", "actor_token has to be one issued to the client presenting it") unless acting.held_by?(client)
    end

    def scopes_only_narrow
      widened = Scopes.refused(available_scopes, requested_scopes)

      if widened.any?
        deny!("invalid_scope",
              "an exchange cannot widen scope: #{widened.join(', ')} is not carried by the subject token")
      end
    end

    def audience_only_narrows
      widened = requested_audience - available_audience

      if widened.any?
        deny!("invalid_target",
              "an exchange cannot widen audience: #{widened.join(', ')} is not carried by the subject token")
      end
    end

    def lifetime_only_shortens
      return if requested_lifetime.nil?

      deny!("invalid_request", "requested lifetime must be positive") unless requested_lifetime.positive?
    end

    def upstream_is_releasable
      return unless upstream?

      access = subject.record

      if requested_scopes.any? || requested_audience.any? || requested_lifetime
        deny!("invalid_request", "an upstream token is released as the connection holds it, without scope, resource or lifetime")
      end

      deny!("invalid_grant", "subject_token was issued to another client") unless access.client_id == client.id
      deny!("unauthorized_client", "only an approved client can be released somebody's account elsewhere") unless client.approved?
      deny!("invalid_target", "audience has to name exactly one connection") if connection.nil?

      if actor.nil? || connection.revoked? || connection.actor_id != actor.id
        deny!("invalid_grant", "that connection is not live for the person this token speaks for")
      end

      deny!("invalid_grant", "#{connection.provider.name} no longer lets applications use it") unless connection.provider.delegating?

      scope = connection.provider.delegation_scope
      deny!("insufficient_scope", "subject_token does not carry #{scope}") unless access.scope_list.include?(scope)

      return if delegation

      deny!("invalid_grant", "#{actor&.identifier || 'that person'} has not let this client use that connection")
    end
end
