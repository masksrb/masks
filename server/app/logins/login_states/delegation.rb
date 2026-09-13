module LoginStates
  class Delegation < LoginState
    HELD = "delegation_handoff".freeze
    WINDOW = 15.minutes
    FRESHNESS = 15.minutes

    accepts :provider, :code, :state, :error, :error_description, :user

    handles "delegation:callback" do
      finish
    end

    def self.pending?(store, params)
      held = store[HELD]
      presented = params["state"]

      held.present? && presented.present? &&
        ActiveSupport::SecurityUtils.secure_compare(presented.to_s, held["state"].to_s)
    end

    def enabled?
      request.present? && !request.device? && actor.present? && wanted.any?
    end

    def factor!
      return unless enabled?

      refuse!("unauthorized_client", "only an approved client can be trusted with somebody's account elsewhere") unless client&.approved?

      missing = wanted.select { |_, provider| provider.nil? }.map(&:first)
      refuse!("invalid_scope", "#{missing.join(', ')} names no provider that lets applications use it") if missing.any?

      return unless touched?(:consent)

      grant!

      waiting = unconnected.first

      return if waiting.nil?

      if login.redirect_to.present?
        prompt!("consent")
      elsif login.store[HELD].present? || request.silent?
        login.store.delete(HELD)
        expire!(:consent)
      else
        start(waiting)
        prompt!("consent")
      end
    end

    def cleanup!
      held = login.store[HELD]

      login.store.delete(HELD) if held && held["expires_at"].to_i <= Time.current.to_i
    end

    def start_over!
      login.store.delete(HELD)
    end

    def undelegated
      return [] unless enabled?

      wanted.reject do |_, provider|
        connection = provider && connection_for(provider)

        connection && ::Delegation.covering(client: client, actor: actor, connection: connection)
      end
    end

    private

      def wanted
        return [] if request.nil? || actor.nil?

        Scopes.delegations(request.scopes_for(actor)).map do |scope|
          [ scope, ::Provider.delegating.find_by(key: Scopes.delegated_provider(scope)) ]
        end
      end

      def unconnected
        wanted.filter_map { |_, provider| provider if provider && connection_for(provider).nil? }
      end

      def connection_for(provider)
        ::Connection.live.where(provider: provider, actor: actor).order(connected_at: :desc).find(&:delegable?)
      end

      def grant!
        wanted.each do |_, provider|
          connection = connection_for(provider)

          ::Delegation.grant!(client: client, actor: actor, connection: connection) if connection
        end
      rescue ::Delegation::Refused => e
        refuse!("access_denied", e.message)
      end

      def start(provider)
        location, handoff = provider.federation.start(callback: callback_url(provider), delegated: true)

        login.store[HELD] = handoff.merge(
          "provider_id" => provider.id,
          "actor_id" => actor.id,
          "rid" => login.rid,
          "expires_at" => WINDOW.from_now.to_i
        )

        login.redirect_to = location
      end

      def finish
        held = login.store.delete(HELD)

        refuse!("access_denied", "connecting took too long; try again") if held.blank? || held["expires_at"].to_i <= Time.current.to_i
        refuse!("access_denied", "connecting was started by somebody else") unless actor && actor.id == held["actor_id"]

        provider = ::Provider.delegating.find_by(id: held["provider_id"])

        refuse!("access_denied", "that provider is no longer available") if provider.nil? || provider.key != update(:provider).to_s

        identity = provider.federation.finish(login.updates, handoff: held, callback: callback_url(provider))

        connect!(provider, identity, provider.federation.tokens)
      rescue ::Provider::Untrusted, ::Provider::Refused, ::Provider::Unreachable, ::Delegation::Refused, ArgumentError => e
        Event.record!(Event::DELEGATION_REFUSED, actor: actor, by: nil, client: client, provider: provider&.key, reason: e.message)

        refuse!("access_denied", "#{provider&.name || 'the provider'} did not connect: #{e.message}")
      end

      def connect!(provider, identity, tokens)
        subject = identity["sub"].presence || (provider.mcp? ? "masks:#{actor.uuid}" : nil)

        raise ::Provider::Untrusted, "#{provider.name} did not say which account that was" if subject.nil?

        taken = ::Connection.live.find_by(provider: provider, subject: subject.to_s)
        mine = ::Connection.live.where(provider: provider, actor: actor)

        raise ::Delegation::Refused, "that #{provider.name} account is connected to somebody else here" if taken && taken.actor_id != actor.id

        if taken.nil? && mine.exists?
          raise ::Delegation::Refused, "that is not the #{provider.name} account connected to you here"
        end

        if taken.nil? && provider.signs_in? && (login.authenticated_at.nil? || login.authenticated_at < FRESHNESS.ago)
          Event.record!(Event::DELEGATION_REFUSED, actor: actor, by: nil, client: client, provider: provider.key, reason: "stale sign-in")

          refuse!("login_required", "sign in again before connecting a #{provider.name} account for the first time")
        end

        connection = ::Connection.record!(provider: provider, actor: actor, identity: identity.merge("sub" => subject))
        connection.hold!(tokens)

        Event.record!(Event::CONNECTION_LINKED, actor: actor, by: nil, provider: provider.key) if taken.nil?

        connection
      end

      def callback_url(provider)
        "#{Current.origin}/login/provider/#{provider.key}/callback"
      end
  end
end
