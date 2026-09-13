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

  attr_reader :provider, :claims, :policy

  def self.resolve!(provider:, claims:, policy: SignInPolicy.default)
    new(provider: provider, claims: claims, policy: policy).resolve!
  end

  def initialize(provider:, claims:, policy: SignInPolicy.default)
    @provider = provider
    @claims = claims
    @policy = policy
  end

  def resolve!
    refuse! "sso-unavailable", "#{provider.name} cannot sign anybody in" unless provider.signs_in?

    held = Connection.live.find_by(provider: provider, subject: subject)

    return returning(held) if held

    admit!

    matched || provisioned || refuse_unknown!
  end

  private

    def subject
      @subject ||= claims["sub"].presence
    end

    def email
      return @email if defined?(@email)

      @email = claims["email"].to_s.strip.downcase.presence
    end

    def claimed_verified?
      [ true, "true" ].include?(claims["email_verified"])
    end

    def verified?
      return false if email.blank?
      return claimed_verified? if claims.key?("email_verified")

      provider.authoritative_for?(email)
    end

    def vouched?
      provider.vouches_for?(email, verified: claimed_verified?)
    end

    def returning(connection)
      sync(connection.actor) if provider.delegate?

      link(connection.actor)
    end

    def admit!
      return if provider.email_domain_list.empty? && policy.email_domains.empty?

      refuse_unconfirmed! unless verified?
      refuse_domain! unless provider.welcomes?(email) && policy.admits?(email)
    end

    def sync(actor)
      actor.assign_attributes(profile)

      if vouched? && email != actor.email && !Actor.where.not(id: actor.id).exists?(email: email)
        actor.assign_attributes(email: email, email_verified_at: Time.current)
      end

      actor.save! if actor.changed?
    rescue ActiveRecord::RecordInvalid
      actor.restore_attributes
    end

    def matched
      return nil unless verified?

      actor = Actor.find_by(email: email)

      return nil if actor.nil?

      if actor.activated?
        refuse_unclaimed! unless actor.email_verified_at?

        return { actor: actor, identity: claims, claiming: true }
      end

      refuse_uninvited! unless vouched?

      link(actor)
    end

    def provisioned
      return nil unless provider.delegate?
      return nil if email.present? && !vouched?
      return nil if email.present? && Actor.exists?(email: email)

      actor = Actor.create!(
        nickname: nickname,
        email: email,
        email_verified_at: (Time.current if email),
        activated_at: Time.current,
        scopes: Scopes.join(provider.signup_scope_list),
        **profile
      )

      Event.record!(
        Event::ACTOR_PROVISIONED,
        actor: actor, by: nil, provider: provider.key, email: email
      )

      link(actor, fresh: true)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      refuse!("sso-no-account", "an account here already answers for that address")
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

      spare(wanted) || refuse!("sso-unavailable", "no nickname was free for that account")
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
        identity: claims
      )

      connection.signed_in!

      Event.record!(Event::CONNECTION_LINKED, actor: actor, by: nil, provider: provider.key) if fresh || connection.previously_new_record?

      { actor: actor, connection: connection }
    end

    def domains
      (provider.email_domain_list | policy.email_domains).join(", ")
    end

    def refuse_domain!
      refuse!(
        "sso-domain-refused",
        "#{provider.name} signed in an address outside #{domains}"
      )
    end

    def refuse_unconfirmed!
      refuse!(
        "sso-unverified",
        "#{provider.name} confirmed no address, and only #{domains} may sign in"
      )
    end

    def refuse_unclaimed!
      refuse!(
        "sso-unverified",
        "an account here holds that address without having confirmed it"
      )
    end

    def refuse_uninvited!
      refuse!(
        "sso-unauthoritative",
        "#{provider.name} does not answer for #{email.to_s.split('@').last}, " \
        "so it cannot take up an invitation waiting there"
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
