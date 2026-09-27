module Masks
  module Server
    module LoginStates
      class EmailCode < LoginState
        HELD = "email_code".freeze
        CHANNEL = "email_sign_in".freeze
        EXPIRY = 12.hours
        WINDOW = 15.minutes

        accepts :code

        handles "email-code:send", limit: :sending do
          send_code
        end

        handles "email-code:verify", limit: :verifying do
          verify
        end

        prompts "email-code" do
          sent? && !login.first_factored?
        end

        def enabled?
          login.policy.first_factor?(:email_code) && ActorMailer.deliverable?
        end

        def as_json
          { "emailCode" => { "offered" => true, "sent" => sent?, "resendable" => resendable? } }
        end

        def start_over!
          login.store.delete(HELD)
        end

        private

          def held
            stored = login.store[HELD]

            stored.present? && stored["identifier"] == login.identifier ? stored : {}
          end

          def sent?
            held["sent"].present?
          end

          def resendable?
            held["sent"].to_i <= ConfirmationCode::RESEND_AFTER.ago.to_i
          end

          def candidate
            found = Masks::Server::Actor.locate(login.identifier)

            found if found&.email.present? && found.activated?
          end

          def token
            return @token if defined?(@token)

            id = held["token_id"]
            found = id && Masks::Server::ConfirmationCode.find_by(id: id)

            @token = found&.live? && found.channel == CHANNEL ? found : nil
          end

          def crowded?(actor)
            recent = Masks::Server::ConfirmationCode.where(actor_id: actor.id, created_at: WINDOW.ago..)
                                                    .where("payload->>'channel' = ?", CHANNEL)

            recent.count >= ::Rails.configuration.masks.recovery_limit
          end

          def send_code
            return warn!("missing-identifier") if login.identifier.blank?
            return if sent? && !resendable?

            remove_instance_variable(:@token) if defined?(@token)
            actor = candidate
            stored = { "identifier" => login.identifier, "sent" => Time.current.to_i }

            if actor
              return warn!("too-many-codes") if crowded?(actor)

              opened, code = Masks::Server::ConfirmationCode.open!(actor: actor, channel: CHANNEL, address: actor.email)
              Masks::Server::Confirmations.deliver(ConfirmationCode::EMAIL, actor.email, code,
                                                   journey: Masks::Server::Journey.sign_in(login))
              stored["token_id"] = opened.id
            end

            login.store[HELD] = stored
          end

          def verify
            return warn!("confirmation-expired") unless sent?

            unless token&.verify(update(:code))
              remove_instance_variable(:@token) if defined?(@token)
              refused! "email-code"
              return warn!("invalid-code")
            end

            actor = token.actor

            login.actor = actor
            factored! :first_factor, expiry: EXPIRY
            login.noted! "otp"
            login.store.delete(HELD)

            confirm!(actor)
          end

          def confirm!(actor)
            return if actor.email_verified_at.present? || !actor.email.to_s.casecmp?(token.address.to_s)

            actor.update!(email_verified_at: Time.current)
            Event.record!(Event::EMAIL_VERIFIED, actor: actor)
          end
      end
    end
  end
end
