module Masks
  module Server
    module AuthenticatorApp
      GROUP = 4
      HELD = "authenticator_setup".freeze

      class << self
        def offered?(actor, policy: SignInPolicy.for(tenant: Current.tenant))
          actor.manages? || policy.second_factor?("otp")
        end

        def backup_codes_offered?(actor, policy: SignInPolicy.for(tenant: Current.tenant))
          actor.manages? || policy.second_factor?("backup_codes")
        end

        def setup_secret(session, actor)
          held = session[HELD]

          return held["secret"] if held.is_a?(Hash) && held["actor_id"] == actor.id

          session[HELD] = { "actor_id" => actor.id, "secret" => ROTP::Base32.random }
          session[HELD]["secret"]
        end

        def grouped(secret)
          secret.scan(/.{1,#{GROUP}}/).join(" ")
        end

        def uri(secret, actor:, tenant: Current.tenant)
          ROTP::TOTP.new(secret, issuer: tenant&.name.presence || "masks").provisioning_uri(actor.identifier)
        end

        def qr(uri)
          RQRCode::QRCode.new(uri).as_svg(
            module_size: 4, use_path: true, viewbox: true, standalone: true,
            color: "000", fill: "fff", offset: 16,
            svg_attributes: { "aria-hidden": "true" }
          ).sub(/\A<\?xml[^>]*>/, "")
        end

        def remove!(actor)
          attributes = { otp_secret: nil, otp_enabled_at: nil }
          attributes.merge!(backup_code_digests: [], backup_codes_generated_at: nil) unless actor.verified_passkeys?

          actor.update!(attributes)
          DeviceFactor.forget!(actor: actor)
        end
      end
    end
  end
end
