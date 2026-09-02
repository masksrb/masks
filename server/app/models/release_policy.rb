class ReleasePolicy < Policy
  checks :connection_is_known,
         :provider_is_active,
         :subject_owns_the_connection,
         :connection_is_live,
         :token_may_release_it

  delegate :token, :connection, :provider, :actor, :required_scope, to: :subject

  private

    def connection_is_known
      deny!("invalid_target", "no such connection", status: :not_found) if connection.nil?
    end

    def provider_is_active
      return unless provider.archived?

      deny!("invalid_target", "#{provider.name} is no longer configured here")
    end

    def subject_owns_the_connection
      return if actor.present? && actor.id == connection.actor_id

      deny!("invalid_target", "no such connection", status: :not_found)
    end

    def token_may_release_it
      return if token.scope_list.include?(required_scope)

      deny!("insufficient_scope",
            "this token does not carry #{required_scope}",
            status: :forbidden)
    end

    def connection_is_live
      return unless connection.revoked?

      deny!("invalid_grant",
            connection.revoked_reason.presence || "that connection has been revoked")
    end
end
