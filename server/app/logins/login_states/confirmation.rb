module LoginStates
  class Confirmation < LoginState
    HELD = "confirmation".freeze

    CHANNELS = {
      ConfirmationCode::EMAIL => { verified: :email_verified_at, event: Event::EMAIL_VERIFIED },
      ConfirmationCode::PHONE => { verified: :phone_verified_at, event: Event::PHONE_VERIFIED }
    }.freeze

    accepts :code, :phone

    handles "confirm:email", limit: :verifying do
      verify(ConfirmationCode::EMAIL)
    end

    handles "confirm:phone", limit: :verifying do
      verify(ConfirmationCode::PHONE)
    end

    handles "confirm:resend", limit: :sending do
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
      open!(ConfirmationCode::EMAIL) unless email_mode == "link"
      unconfirmed?(ConfirmationCode::EMAIL)
    end

    prompts "confirm-phone" do
      open!(ConfirmationCode::PHONE)
      unconfirmed?(ConfirmationCode::PHONE)
    end

    def enabled?
      actor.present? && login.first_factored? &&
        (actor.pending_approval_at.present? || phone_missing? || CHANNELS.keys.any? { |channel| unconfirmed?(channel) })
    end

    def as_json
      {
        "confirmation" => {
          "email" => actor.email,
          "phone" => actor.phone,
          "mode" => email_mode,
          "mails" => ActorMailer.deliverable?,
          "texts" => Texting.deliverable?,
          "resendable" => CHANNELS.keys.all? { |channel| resendable?(channel) }
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

      def held
        stored = login.store[HELD]

        stored.present? && stored["actor_id"] == actor.id ? stored : { "actor_id" => actor.id }
      end

      def email_mode
        policy.confirmation == SignInPolicy::LINK && actor.signed_up_at.present? ? "link" : ConfirmationCode::EMAIL
      end

      def unconfirmed?(channel)
        return false if actor.public_send(channel).blank? || actor.public_send(CHANNELS[channel][:verified]).present?

        if channel == ConfirmationCode::EMAIL
          policy.email_verified ||
            (actor.signed_up_at.present? && [ SignInPolicy::CODE, SignInPolicy::LINK ].include?(policy.confirmation))
        else
          policy.asks?(:phone) && policy.phone_verified
        end
      end

      def phone_missing?
        policy.requires?(:phone) && actor.phone.blank?
      end

      def token_for(channel)
        @tokens ||= {}

        return @tokens[channel] if @tokens.key?(channel)

        id = held[channel]
        token = id && ConfirmationCode.find_by(id: id, actor_id: actor.id)

        @tokens[channel] = token&.live? && token.channel == channel ? token : nil
      end

      def resendable?(channel)
        token_for(channel)&.resendable? != false
      end

      def open!(channel)
        return unless unconfirmed?(channel)
        return if token_for(channel) || held["#{channel}_sent"].present?

        send_code(channel)
      end

      def send_code(channel)
        token = Confirmations.send_code(actor, channel)

        @tokens&.delete(channel)
        login.store[HELD] = held.merge(channel => token.id, "#{channel}_sent" => Time.current.to_i)
      end

      def forget!(channel)
        @tokens&.delete(channel)
        login.store[HELD] = held.except(channel, "#{channel}_sent")
      end

      def verify(channel)
        token = token_for(channel)

        return warn!("confirmation-expired") if token.nil?

        if token.verify(update(:code)) && token.address == actor.public_send(channel)
          actor.update!(CHANNELS[channel][:verified] => Time.current)

          Event.record!(CHANNELS[channel][:event], actor: actor)

          forget!(channel)
        else
          @tokens.delete(channel)
          refused! "confirm_#{channel}"
          warn! "invalid-code"
        end
      end

      def resend
        if unconfirmed?(ConfirmationCode::EMAIL)
          if email_mode == "link"
            Verifications.open(actor: actor)
          elsif resendable?(ConfirmationCode::EMAIL)
            send_code(ConfirmationCode::EMAIL)
          end
        end

        send_code(ConfirmationCode::PHONE) if unconfirmed?(ConfirmationCode::PHONE) && resendable?(ConfirmationCode::PHONE)
      end

      def change_phone
        return unless unconfirmed?(ConfirmationCode::PHONE)

        actor.update!(phone: nil, phone_verified_at: nil)
        forget!(ConfirmationCode::PHONE)
      end

      def add_phone
        return unless phone_missing? || unconfirmed?(ConfirmationCode::PHONE)

        number = Adapters::Sms.number(update(:phone))

        return warn!("invalid-phone", field: "phone") if number.nil?
        return warn!("invalid-account", field: "phone") unless actor.update(phone: number, phone_verified_at: nil)

        forget!(ConfirmationCode::PHONE)
      end
  end
end
