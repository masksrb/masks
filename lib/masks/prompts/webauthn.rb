module Masks
  module Prompts
    class Webauthn
      include Masks::Prompt

      match { current_client.allow_webauthn? }

      setting :webauthn_id, :string
      setting :webauthn_registration, :json
      setting :webauthn_verification, :json

      setting :delete_webauthn_id, :string

      setup do
        session.structure do
          key :webauthn_registration,
              parent: :endpoint,
              expiry: 10.minutes.from_now
          key :webauthn_challenge,
              parent: :endpoint,
              expiry: 10.minutes.from_now
        end
      end

      event "webauthn:register" do
        options =
          WebAuthn::Credential.options_for_create(
            attestation: "direct",
            user: {
              id: current_actor.webauthn_id,
              name: current_actor.identifier,
            },
            exclude: current_actor.hardware_keys.pluck(:external_id),
          )

        extras(webauthn: options)

        session[:webauthn_registration] = options.challenge
      end

      event "webauthn:create", if: :change_2fa? do
        webauthn = WebAuthn::Credential.from_create(webauthn_registration)

        begin
          webauthn.verify(session[:webauthn_registration])
          credential =
            Masks::HardwareKey.new(
              name: Masks::Shims::Fido.aaguid_name(webauthn.response.aaguid),
              actor: current_actor,
              aaguid: webauthn.response.aaguid,
              external_id: webauthn.id,
              public_key: webauthn.public_key,
              sign_count: webauthn.sign_count,
              verified_at: Time.now.utc,
            )

          if credential.save
            session[Prompt::FACTOR2] = current_client.expires_at(:webauthn_2fa)
          else
            warn! "webauthn-error"
          end
        rescue WebAuthn::Error => e
          warn! "webauthn-error"
        end
      end

      event "webauthn:challenge" do
        webauthn =
          WebAuthn::Credential.options_for_get(
            allow: current_actor.hardware_keys.map { |c| c.external_id },
          )

        extras(webauthn:)

        session[:webauthn_challenge] = webauthn.challenge
      end

      event "webauthn:verify", if: :on_2fa? do
        verify
      end

      event "webauthn:delete", if: :change_2fa? do
        if delete_webauthn_id
          current_actor
            .hardware_keys
            .find_by(external_id: delete_webauthn_id)
            &.destroy
        end
      end

      def verify
        return unless current_client.allow_webauthn? && webauthn_verification

        webauthn = WebAuthn::Credential.from_get(webauthn_verification)
        credential =
          current_actor&.hardware_keys&.find_by(external_id: webauthn.id)
        challenge = session[:webauthn_challenge]

        return warn! "invalid-webauthn" unless credential && challenge

        begin
          webauthn.verify(
            challenge,
            public_key: credential.public_key,
            sign_count: credential.sign_count,
          )

          credential.update!(
            sign_count: webauthn.sign_count,
            verified_at: Time.now.utc,
          )

          session[Prompt::FACTOR2] = current_client.expires_at(:webauthn_2fa)
        rescue => e
          warn! "webauthn-error"
        end
      end
    end
  end
end
