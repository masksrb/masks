class SingleSignOn
  class Refused < StandardError
    attr_reader :warning

    def initialize(warning, message)
      super(message)

      @warning = warning.to_s
    end
  end

  NICKNAME = /\A[a-z0-9][a-z0-9._-]*\z/i
  SPARE = 500

  attr_reader :provider, :claims, :tokens

  def self.resolve!(provider:, claims:, tokens:)
    new(provider: provider, claims: claims, tokens: tokens).resolve!
  end

  def initialize(provider:, claims:, tokens:)
    @provider = provider
    @claims = claims
    @tokens = tokens
  end

  def resolve!
    refuse! "sso-unavailable", "#{provider.name} cannot sign anybody in" unless provider.signs_in?

    held = Connection.live.find_by(provider: provider, subject: subject)

    return returning(held) if held

    refuse_domain! unless email.nil? || provider.welcomes?(email)

    claimed || provisioned || refuse_unknown!
  end

  private

    def subject
      @subject ||= claims[provider.subject_claim].presence || claims["sub"].presence
    end

    def email
      return @email if defined?(@email)

      @email = claims["email"].to_s.strip.downcase.presence
    end

    def verified?
      email.present? && claims["email_verified"] == true
    end

    def returning(connection)
      link(connection.actor)
    end

    def claimed
      return nil unless verified?

      actor = Actor.find_by(email: email)

      return nil if actor.nil?

      link(actor)
    end

    def provisioned
      return nil unless provider.provisions?
      return nil if email.present? && Actor.exists?(email: email)

      actor = Actor.create!(
        nickname: nickname,
        email: email,
        email_verified_at: (Time.current if verified?),
        activated_at: Time.current,
        scopes: Scopes.join(provider.signup_scope_list),
        **profile
      )

      Event.record!(
        Event::ACTOR_PROVISIONED,
        actor: actor, by: nil, provider: provider.key, email: email
      )

      link(actor, fresh: true)
    end

    def profile
      Actor::PROFILE_CLAIMS.each_with_object({}) do |(claim, column), held|
        next if column == :nickname

        value = claims[claim].presence

        held[column] ||= value if value
      end
    end

    def nickname
      wanted = [ claims["preferred_username"], email&.split("@")&.first, provider.key ]
        .filter_map { |value| tidy(value) }
        .first

      return wanted unless Actor.exists?(nickname: wanted)

      spare(wanted) || refuse!("sso-unavailable", "no username was free for that account")
    end

    def tidy(value)
      held = value.to_s.strip.downcase.gsub(/[^a-z0-9._-]/, "-").gsub(/-+/, "-").delete_prefix("-")

      held.presence && held.match?(NICKNAME) ? held : nil
    end

    def spare(wanted)
      (2..SPARE).each do |at|
        candidate = "#{wanted}#{at}"

        return candidate unless Actor.exists?(nickname: candidate)
      end

      nil
    end

    def link(actor, fresh: false)
      connection = Connection.record!(
        provider: provider,
        actor: actor,
        tokens: tokens,
        identity: claims
      )

      connection.signed_in!

      Event.record!(Event::CONNECTION_LINKED, actor: actor, by: nil, provider: provider.key) if fresh || connection.previously_new_record?

      { actor: actor, connection: connection }
    end

    def refuse_domain!
      refuse!(
        "sso-domain-refused",
        "#{provider.name} signed in an address outside #{provider.email_domain_list.join(', ')}"
      )
    end

    def refuse_unknown!
      return refuse!("sso-unverified", "#{provider.name} did not confirm that address belongs to them") if email && !verified?

      refuse!("sso-no-account", "no account here matches that #{provider.name} sign-in")
    end

    def refuse!(warning, message)
      raise Refused.new(warning, message)
    end
end
