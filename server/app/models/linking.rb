class Linking
  class Refused < StandardError; end

  HELD = "provider_linking".freeze
  WINDOW = 15.minutes
  FRESHNESS = 15.minutes

  class << self
    def offered(actor)
      policy = SignInPolicy.for
      linked = Connection.live.where(actor: actor).pluck(:provider_id)

      return [] unless policy.first_factor?(:provider)

      Provider.signing_in.where.not(id: linked).order(:name).select { |provider| policy.offers?(provider) }
    end

    def start!(session:, provider:, actor:, authenticated_at:)
      raise Refused, I18n.t("connections.unavailable") if provider.nil? || !offered(actor).include?(provider)
      raise Refused, I18n.t("connections.stale") if authenticated_at.nil? || authenticated_at < FRESHNESS.ago

      location, handoff = provider.federation.start(callback: callback_for(provider))

      session[HELD] = handoff.merge(
        "provider_id" => provider.id,
        "actor_id" => actor.id,
        "expires_at" => WINDOW.from_now.to_i
      )

      location
    end

    def pending?(session, params)
      held = session[HELD]

      presented = params["RelayState"].presence || params["state"]

      held.present? && presented.present? &&
        ActiveSupport::SecurityUtils.secure_compare(presented.to_s, held["state"].to_s)
    end

    def finish!(session:, provider:, actor:, params:)
      held = session.delete(HELD)

      raise Refused, I18n.t("connections.expired") if held.blank? || held["expires_at"].to_i <= Time.current.to_i
      raise Refused, I18n.t("connections.expired") unless actor && actor.id == held["actor_id"]
      raise Refused, I18n.t("connections.unavailable") unless provider && provider.id == held["provider_id"]

      identity = provider.federation.finish(params, handoff: held, callback: callback_for(provider))

      link!(provider, actor, identity)
    rescue Provider::Untrusted, Provider::Refused, Provider::Unreachable => e
      Event.record!(Event::CONNECTION_REFUSED, actor: actor, by: nil, provider: provider&.key, reason: e.message)

      raise Refused, I18n.t("connections.failed", provider: provider&.name)
    end

    def callback_for(provider)
      "#{Current.origin}/login/provider/#{provider.key}/callback"
    end

    private

      def link!(provider, actor, identity)
        held = Connection.find_by(provider: provider, subject: identity["sub"].to_s)

        if held && !held.revoked? && held.actor_id != actor.id
          Event.record!(Event::CONNECTION_REFUSED, actor: actor, by: nil, provider: provider.key, reason: "already linked to another account")

          raise Refused, I18n.t("connections.taken", provider: provider.name)
        end

        connection = Connection.record!(provider: provider, actor: actor, identity: identity)

        Event.record!(Event::CONNECTION_LINKED, actor: actor, by: nil, provider: provider.key)

        connection
      end
  end
end
