module LoginStates
  class Enrolment < LoginState
    HELD = "enrolment".freeze
    WINDOW = 15.minutes
    GROUP = 4

    accepts :code, :passkey, :kept

    handles "enrol:otp" do
      enrol_otp
    end

    handles "enrol:passkey-challenge" do
      offer_passkey
    end

    handles "enrol:passkey" do
      enrol_passkey
    end

    handles "enrol:done" do
      finish
    end

    prompts "enrol" do
      open! if required? || offered_at_signup?
      open?
    end

    def enabled?
      actor.present? && login.first_factored? && (required? || open? || offered_at_signup?)
    end

    def as_json
      signing_up = login.store[Signup::SIGNED_UP]

      {
        "enrolment" => {
          "required" => required?,
          "signingUp" => signing_up,
          "steps" => signing_up && Signup.steps(signing_up["first_run"]),
          "offers" => offers,
          "otp" => otp_json,
          "passkeys" => {
            "count" => actor.passkeys.count,
            "verified" => actor.verified_passkeys?,
            "options" => held.dig("passkey", "options")
          }.compact,
          "backupCodes" => {
            "issued" => held["codes"],
            "remaining" => actor.backup_codes_remaining
          }.compact
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
    end

    def cleanup!
      stored = login.store[HELD]

      login.store.delete(HELD) if stored.present? && stored["expires_at"].to_i <= Time.current.to_i
    end

    def required?
      login.first_factored? && !actor.second_factor? && (actor.manages? || login.policy.second_factor_required)
    end

    def offers
      offered = actor.manages? ? SignInPolicy::SECOND_FACTORS : login.policy.second_factors

      { "otp" => offered.include?("otp"), "passkey" => offered.include?("passkey"),
        "backupCodes" => offered.include?("backup_codes") }
    end

    private

      def held
        stored = login.store[HELD]

        stored.present? && stored["actor_id"] == actor.id ? stored : {}
      end

      def open?
        held.present?
      end

      def offered_at_signup?
        signed_up = login.store[Signup::SIGNED_UP]

        signed_up.present? && !signed_up["enrolment_offered"] && (offers["otp"] || offers["passkey"])
      end

      def open!
        return if open?

        signed_up = login.store[Signup::SIGNED_UP]
        login.store[Signup::SIGNED_UP] = signed_up.merge("enrolment_offered" => true) if signed_up.present?

        login.store[HELD] = { "actor_id" => actor.id, "expires_at" => (Time.current + WINDOW).to_i }
      end

      def hold(**values)
        login.store[HELD] = held.merge(values.stringify_keys)
      end

      def otp_json
        return { "enabled" => true } if actor.otp?

        secret = otp_secret

        {
          "enabled" => false,
          "secret" => secret.scan(/.{1,#{GROUP}}/).join(" "),
          "uri" => uri(secret),
          "qr" => qr(secret)
        }
      end

      def otp_secret
        held["otp_secret"] || (open? && hold(otp_secret: ROTP::Base32.random)["otp_secret"]) ||
          ROTP::Base32.random
      end

      def enrol_otp
        return unless open? && !actor.otp? && offers["otp"]

        secret = otp_secret
        totp = ROTP::TOTP.new(secret)
        at = totp.verify(update(:code).to_s.delete("^0-9"), drift_behind: Actor::OTP_DRIFT)

        if at.nil?
          refused! "enrol_otp"
          return warn!("invalid-code")
        end

        actor.update!(otp_secret: secret, otp_enabled_at: Time.current,
                      otp_last_step: at.to_i / totp.interval)

        Event.record!(Event::AUTHENTICATOR_ENABLED, actor: actor)

        hold(otp_secret: nil)
        enrolled! "otp", "mfa"
      end

      def offer_passkey
        return unless open? && offers["passkey"]

        options = relying_party.registration_options(actor, user_verification: "required")

        hold(passkey: { "challenge" => options.challenge, "options" => options.as_json })
      end

      def enrol_passkey
        return unless open? && offers["passkey"]

        challenge = held.dig("passkey", "challenge")
        hold(passkey: nil)

        return warn!("passkey-expired") if challenge.blank?
        return warn!("passkey-crowded") if actor.passkeys.count >= ::Passkey::MAX_PER_ACTOR

        credential = relying_party.verify_registration(JSON.parse(update(:passkey).to_s), challenge)

        unless credential.response.authenticator_data.user_verified?
          refused! "enrol_passkey"
          return warn!("passkey-unverified")
        end

        passkey = ::Passkey.enrol!(actor: actor, credential: credential, name: nil)

        Event.record!(Event::PASSKEY_ADDED, actor: actor, passkey: passkey.name)

        enrolled! "swk", "user", "mfa"
      rescue WebAuthn::Error, JSON::ParserError, ActiveRecord::RecordInvalid
        refused! "enrol_passkey"
        warn! "passkey-unusable"
      end

      def enrolled!(*methods)
        if offers["backupCodes"] && !actor.backup_codes?
          codes = actor.generate_backup_codes!

          Event.record!(Event::BACKUP_CODES_GENERATED, actor: actor, count: codes.length)

          hold(codes: codes)
        end

        factored! :second_factor, expiry: OneTimePassword::EXPIRY
        login.noted!(*methods)
      end

      def finish
        return unless open?
        return warn!("second-factor-required") if required?
        return warn!("backup-codes-unkept") if held["codes"].present? && !kept?

        login.store.delete(HELD)
      end

      def kept?
        ActiveModel::Type::Boolean.new.cast(update(:kept))
      end

      def uri(secret)
        ROTP::TOTP.new(secret, issuer: tenant&.name.presence || "masks")
                  .provisioning_uri(actor.identifier)
      end

      def qr(secret)
        RQRCode::QRCode.new(uri(secret)).as_svg(
          module_size: 4, use_path: true, viewbox: true, standalone: true,
          color: "000", fill: "fff", offset: 16,
          svg_attributes: { "aria-hidden": "true" }
        ).sub(/\A<\?xml[^>]*>/, "")
      end

      def relying_party
        RelyingParty.for(tenant, Current.origin)
      end
  end
end
