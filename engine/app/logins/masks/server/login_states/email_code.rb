module Masks
  module Server
    module LoginStates
      class EmailCode < LoginState
        HELD = "email_code".freeze
        CHANNEL = "email_sign_in".freeze
        EXPIRY = 12.hours

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
          return @enabled if defined?(@enabled)

          @enabled = login.policy.first_factor?(:email_code) && ActorMailer.deliverable?
        end

        def as_json
          { "emailCode" => { "sent" => sent?, "resendable" => resendable? } }
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

          def send_code
            return warn!("missing-identifier") if login.identifier.blank?
            return if sent? && !resendable?

            actor = candidate
            stored = { "identifier" => login.identifier, "sent" => Time.current.to_i }

            if actor
              return warn!("too-many-codes") if Masks::Server::ConfirmationCode.crowded?(actor: actor, channel: CHANNEL)

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
              refused! "email-code"
              return warn!("invalid-code")
            end

            actor = token.actor

            login.actor = actor
            factored! :first_factor, expiry: EXPIRY
            login.noted! "otp"
            login.store.delete(HELD)

            actor.verify_email!(token.address)
          end
      end
    end
  end
end
