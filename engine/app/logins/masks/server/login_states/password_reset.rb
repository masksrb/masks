module Masks
  module Server
    module LoginStates
      class PasswordReset < LoginState
        EXPIRY = 12.hours
        HELD = "reset".freeze
        SENT = "reset-sent".freeze

        accepts :password

        handles "forgot-password", limit: :sending do
          open
        end

        handles "reset-password" do
          settle
        end

        prompts "reset-password" do
          reset.present?
        end

        def reload!
          @loaded = false
          @reset = nil
        end

        def as_json
          held = reset
          return {} if held.nil?

          {
            "reset" => {
              "nickname" => held.actor.identifier,
              "minimum" => login.policy.password_minimum
            }
          }
        end

        def start_over!
          login.store.delete(HELD)
          reload!
        end

        def reset
          return @reset if @loaded

          @loaded = true
          secret = login.store[HELD]
          @reset = secret.present? ? Masks::Server::PasswordReset.redeem(secret) : nil
        end

        private

          def open
            return warn!("missing-identifier") if login.identifier.blank?
            return warn!("no-mailer") unless ActorMailer.deliverable?

            Recoveries.request(identifier: login.identifier)

            warn! SENT
          end

          def settle
            return warn!("reset-expired") if reset.nil?
            refusal = Passwords.refusal(password, login.policy)
            return warn!(refusal, field: "password") if refusal

            actor = Masks::Server::PasswordReset.settle!(login.store[HELD], password)
            return warn!("reset-expired") if actor.nil?

            Event.record!(Event::PASSWORD_RESET_COMPLETED, actor: actor)

            login.store.delete(HELD)
            reload!
            login.identifier = actor.identifier
            login.actor = actor
            factored! :first_factor, expiry: EXPIRY
          end

          def password
            update(:password).to_s
          end
      end
    end
  end
end
