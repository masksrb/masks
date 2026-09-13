module LoginStates
  class Provider < LoginState
    EXPIRY = 12.hours
    WINDOW = 15.minutes
    HELD = "provider_handoff".freeze
    CLAIM = "provider_claim".freeze

    accepts :provider, :code, :state, :error, :error_description, :user

    handles "provider" do
      start
    end

    handles "provider:callback" do
      finish
    end

    def enabled?
      ::Actor.exists? && offered.any?
    end

    def as_json
      {
        "providers" => offered.map { |provider| { "key" => provider.key, "name" => provider.name } }
      }
    end

    def start_over!
      login.store.delete(HELD)
      login.store.delete(CLAIM)
    end

    def factor!
      return unless enabled?

      attach!

      super
    end

    def cleanup!
      [ HELD, CLAIM ].each do |key|
        held = login.store[key]

        login.store.delete(key) if held && held["expires_at"].to_i <= Time.current.to_i
      end
    end

    private

      def offered
        @offered ||= if login.policy.first_factor?(:provider)
          ::Provider.signing_in.order(:name).select { |provider| login.policy.offers?(provider) }
        else
          []
        end
      end

      def start
        provider = offered.find { |one| one.key == update(:provider).to_s }

        return warn!("sso-unavailable") if provider.nil?

        location, handoff = provider.federation.start(callback: callback_url(provider))

        login.store[HELD] = handoff.merge(
          "provider_id" => provider.id,
          "rid" => login.rid,
          "expires_at" => WINDOW.from_now.to_i
        )

        login.redirect_to = location
      end

      def finish
        held = login.store.delete(HELD)

        return warn!("sso-expired") if held.blank? || held["expires_at"].to_i <= Time.current.to_i

        provider = offered.find { |one| one.id == held["provider_id"] }

        return warn!("sso-unavailable") if provider.nil? || provider.key != update(:provider).to_s

        identity = provider.federation.finish(login.updates, handoff: held, callback: callback_url(provider))
        settled = SingleSignOn.resolve!(provider: provider, claims: identity, policy: login.policy)

        signed_in(provider, settled)
      rescue SingleSignOn::Refused => e
        refuse(e.warning, provider, e.message)
      rescue ::Provider::Untrusted, ::Provider::Refused, ::Provider::Unreachable, ArgumentError, OpenSSL::PKey::PKeyError => e
        refuse("sso-failed", provider, e.message)
      end

      def signed_in(provider, settled)
        actor = settled[:actor]

        return claim!(provider, actor, settled[:identity]) if settled[:claiming]

        login.identifier = actor.identifier
        login.actor = actor

        factored! :first_factor, expiry: EXPIRY
        login.noted! provider.protocol

        Event.record!(
          Event::CONNECTION_SIGNED_IN,
          actor: actor, by: nil, provider: provider.key
        )
      end

      def claim!(provider, actor, identity)
        login.store[CLAIM] = {
          "provider_id" => provider.id,
          "actor_id" => actor.id,
          "identity" => identity.slice("sub", "email", "email_verified", "preferred_username", "name"),
          "expires_at" => WINDOW.from_now.to_i
        }

        login.identifier = actor.identifier

        warn! "sso-claiming"
      end

      def attach!
        held = login.store[CLAIM]

        return if held.blank?
        return unless login.actor&.id == held["actor_id"] && login.touched?(:first_factor)

        provider = ::Provider.signing_in.find_by(id: held["provider_id"])

        login.store.delete(CLAIM)

        return if provider.nil?

        Connection.record!(
          provider: provider, actor: login.actor, identity: held["identity"]
        ).signed_in!

        login.noted! provider.protocol

        Event.record!(
          Event::CONNECTION_LINKED,
          actor: login.actor, by: nil, provider: provider.key
        )
      end

      def refuse(warning, provider, description)
        Event.record!(
          Event::CONNECTION_REFUSED,
          actor: nil, by: nil, provider: provider.key, reason: description
        )

        warn! warning
      end

      def callback_url(provider)
        "#{Current.origin}/login/provider/#{provider.key}/callback"
      end
  end
end
