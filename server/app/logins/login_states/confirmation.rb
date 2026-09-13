module LoginStates
  class Confirmation < LoginState
    HELD = "confirmation".freeze

    accepts :code, :phone

    handles "confirm:email" do
      verify(ConfirmationCode::EMAIL)
    end

    handles "confirm:phone" do
      verify(ConfirmationCode::PHONE)
    end

    handles "confirm:resend" do
      resend
    end

    handles "confirm:add-phone" do
      add_phone
    end

    handles "confirm:change-phone" do
      change_phone
    end

    handles "confirm:check" do
      actor&.reload
    end

    prompts "awaiting-approval" do
      actor.pending_approval_at.present?
    end

    prompts "add-phone" do
      phone_missing?
    end

    prompts "confirm-email" do
      open!(ConfirmationCode::EMAIL) if email_mode == ConfirmationCode::EMAIL
      email_unconfirmed?
    end

    prompts "confirm-phone" do
      open!(ConfirmationCode::PHONE)
      phone_unconfirmed?
    end

    def enabled?
      actor.present? && login.first_factored? && !enrolling? &&
        (actor.pending_approval_at.present? || phone_missing? || email_unconfirmed? || phone_unconfirmed?)
    end

    def as_json
      signed_up = login.store[Signup::SIGNED_UP]

      {
        "confirmation" => {
          "email" => actor.email,
          "phone" => actor.phone,
          "mode" => email_mode,
          "mails" => ActorMailer.deliverable?,
          "texts" => Texting.deliverable?,
          "signingUp" => signed_up.present? && !signed_up["first_run"],
          "steps" => Signup.steps(false, login.policy),
          "resendable" => resendable?
        }
      }
    end

    def start_over!
      login.store.delete(HELD)
    end

    private

      def policy
        login.policy
      end

      def enrolling?
        login.store[Enrolment::HELD].present?
      end

      def held
        stored = login.store[HELD]

        stored.present? && stored["actor_id"] == actor.id ? stored : { "actor_id" => actor.id }
      end

      def email_mode
        policy.confirmation == SignInPolicy::LINK && actor.signed_up_at.present? ? "link" : ConfirmationCode::EMAIL
      end

      def email_unconfirmed?
        return false if actor.email.blank? || actor.email_verified_at.present?

        policy.email_verified ||
          (actor.signed_up_at.present? && [ SignInPolicy::CODE, SignInPolicy::LINK ].include?(policy.confirmation))
      end

      def phone_missing?
        policy.requires?(:phone) && actor.phone.blank?
      end

      def phone_unconfirmed?
        policy.asks?(:phone) && policy.phone_verified && actor.phone.present? && actor.phone_verified_at.nil?
      end

      def token_for(channel)
        id = held[channel]
        token = id && ConfirmationCode.find_by(id: id, actor_id: actor.id)

        token if token&.live? && token.channel == channel
      end

      def open!(channel)
        return unless channel == ConfirmationCode::EMAIL ? email_unconfirmed? : phone_unconfirmed?
        return if token_for(channel)
        return if held["#{channel}_sent"].present?

        send_code(channel)
      end

      def send_code(channel)
        token = channel == ConfirmationCode::EMAIL ? Confirmations.send_email_code(actor) : Confirmations.send_phone_code(actor)

        login.store[HELD] = held.merge(channel => token.id, "#{channel}_sent" => Time.current.to_i)
      end

      def verify(channel)
        token = token_for(channel)

        return warn!("confirmation-expired") if token.nil?

        if token.verify(update(:code)) && token.address == actor.public_send(channel)
          column = channel == ConfirmationCode::EMAIL ? :email_verified_at : :phone_verified_at

          actor.update!(column => Time.current)

          Event.record!(channel == ConfirmationCode::EMAIL ? Event::EMAIL_VERIFIED : Event::PHONE_VERIFIED, actor: actor)

          login.store[HELD] = held.except(channel, "#{channel}_sent")
        else
          refused! "confirm_#{channel}"
          warn! "invalid-code"
        end
      end

      def resendable?
        %w[email phone].all? { |channel| token_for(channel).nil? || token_for(channel).resendable? }
      end

      def resend
        if email_unconfirmed?
          if email_mode == "link"
            Verifications.open(actor: actor)
          elsif token_for(ConfirmationCode::EMAIL).nil? || token_for(ConfirmationCode::EMAIL).resendable?
            send_code(ConfirmationCode::EMAIL)
          end
        end

        return unless phone_unconfirmed?
        return unless token_for(ConfirmationCode::PHONE).nil? || token_for(ConfirmationCode::PHONE).resendable?

        send_code(ConfirmationCode::PHONE)
      end

      def change_phone
        return unless phone_unconfirmed?

        actor.update!(phone: nil, phone_verified_at: nil)
        login.store[HELD] = held.except(ConfirmationCode::PHONE, "#{ConfirmationCode::PHONE}_sent")
      end

      def add_phone
        return unless phone_missing? || phone_unconfirmed?

        number = Adapters::Sms.number(update(:phone))

        return warn!("invalid-phone") if number.nil?
        return warn!("invalid-account") unless actor.update(phone: number, phone_verified_at: nil)

        login.store[HELD] = held.except(ConfirmationCode::PHONE, "#{ConfirmationCode::PHONE}_sent")
      end
  end
end
