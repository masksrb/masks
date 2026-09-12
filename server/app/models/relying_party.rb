class RelyingParty
  TIMEOUT = 120_000

  def self.for(tenant = Current.tenant, origin = Current.origin)
    new(tenant, origin)
  end

  attr_reader :tenant, :origin

  def initialize(tenant, origin)
    @tenant = tenant
    @origin = origin
  end

  def id
    URI.parse(origin).host
  end

  def party
    @party ||= WebAuthn::RelyingParty.new(
      allowed_origins: [ origin ],
      name: tenant&.name.presence || id,
      id: id
    )
  end

  def registration_options(actor)
    party.options_for_registration(
      user: {
        id: handle_for(actor),
        name: actor.email.presence || actor.nickname,
        display_name: actor.name.presence || actor.identifier
      },
      exclude: Passkey.where(actor_id: actor.id).pluck(:external_id),
      authenticator_selection: {
        resident_key: "preferred",
        user_verification: "preferred"
      }
    )
  end

  def authentication_options(actor = nil)
    party.options_for_authentication(
      allow: actor ? Passkey.where(actor_id: actor.id).pluck(:external_id) : [],
      user_verification: "preferred"
    )
  end

  def verify_registration(response, challenge)
    credential = WebAuthn::Credential.from_create(response, relying_party: party)
    credential.verify(challenge)
    credential
  end

  def verify_authentication(response, challenge, passkey)
    credential = WebAuthn::Credential.from_get(response, relying_party: party)

    credential.verify(
      challenge,
      public_key: passkey.public_key,
      sign_count: passkey.sign_count
    )

    credential
  end

  def handle_for(actor)
    actor.webauthn_id.presence || actor.tap { |held|
      held.update!(webauthn_id: WebAuthn.generate_user_id)
    }.webauthn_id
  end
end
